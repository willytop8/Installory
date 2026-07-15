import Foundation
import Testing
@testable import InstalloryCore

@Suite("PythonInterpreterDiscovery")
struct PythonInterpreterDiscoveryTests {
    private func buildProvider() throws -> InMemoryDirectoryAccessProvider {
        try FixtureResource.provider(
            directory: "python",
            mappedTo: URL(fileURLWithPath: "/")
        )
    }

    private func discover() throws -> [PythonInterpreter] {
        let provider = try buildProvider()
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/"),
            environment: .empty
        )
        return discovery.discover()
    }

    @Test("discovers pyenv, homebrew (Apple Silicon + Intel), and system fixture interpreters")
    func discoversFixtureInterpreters() throws {
        let interpreters = try discover()
        #expect(interpreters.count == 4)
        #expect(interpreters.contains { $0.executable.path == "/.pyenv/versions/3.11.7/bin/python" })
        #expect(interpreters.contains { $0.executable.path == "/opt/homebrew/opt/python@3.12/bin/python3.12" })
        #expect(interpreters.contains { $0.executable.path == "/usr/bin/python3" })
        #expect(interpreters.contains { $0.executable.path == "/usr/local/opt/python@3.12/bin/python3.12" })
    }

    @Test("assigns interpreter kinds")
    func assignsKinds() throws {
        let interpreters = try discover()

        let pyenv = try #require(interpreters.first { $0.executable.path.contains(".pyenv") })
        let homebrewApple = try #require(interpreters.first { $0.executable.path.contains("/opt/homebrew") })
        let homebrewIntel = try #require(interpreters.first { $0.executable.path.contains("/usr/local/opt") })
        let system = try #require(interpreters.first { $0.executable.path == "/usr/bin/python3" })

        #expect(pyenv.kind == .pyenv)
        #expect(homebrewApple.kind == .homebrew)
        #expect(homebrewIntel.kind == .homebrew)
        #expect(system.kind == .system)
    }

    @Test("PythonVersion parses raw and prefixed version strings")
    func parsesVersionStrings() throws {
        let raw = try #require(PythonInterpreter.PythonVersion("3.11.7"))
        let prefixed = try #require(PythonInterpreter.PythonVersion("Python 3.11.7"))
        let atStyle = try #require(PythonInterpreter.PythonVersion("python@3.12"))
        let majorMinor = try #require(PythonInterpreter.PythonVersion("3.12"))

        #expect(raw == PythonInterpreter.PythonVersion(major: 3, minor: 11, patch: 7))
        #expect(prefixed == raw)
        #expect(atStyle == PythonInterpreter.PythonVersion(major: 3, minor: 12, patch: 0))
        #expect(majorMinor == PythonInterpreter.PythonVersion(major: 3, minor: 12, patch: 0))
    }

    @Test("PythonVersion rejects single-component and non-version strings")
    func rejectsInvalidVersionStrings() {
        #expect(PythonInterpreter.PythonVersion("python3") == nil)
        #expect(PythonInterpreter.PythonVersion("python") == nil)
        #expect(PythonInterpreter.PythonVersion("3") == nil)
        #expect(PythonInterpreter.PythonVersion("") == nil)
    }

    @Test("sitePackages paths point at fixture directories")
    func sitePackagesPaths() throws {
        let interpreters = try discover()

        let pyenv = try #require(interpreters.first { $0.kind == .pyenv })
        let homebrewApple = try #require(interpreters.first { $0.executable.path.contains("/opt/homebrew") })

        #expect(pyenv.sitePackages == [
            URL(fileURLWithPath: "/.pyenv/versions/3.11.7/lib/python3.11/site-packages"),
        ])
        #expect(homebrewApple.sitePackages == [
            URL(fileURLWithPath: "/opt/homebrew/opt/python@3.12/lib/python3.12/site-packages"),
        ])
    }

    @Test("system interpreter is read-only and user interpreters are not")
    func systemReadOnlyFlag() throws {
        let interpreters = try discover()

        let system = try #require(interpreters.first { $0.kind == .system })
        let nonSystem = interpreters.filter { $0.kind != .system }

        #expect(system.isSystem == true)
        #expect(system.sitePackages.isEmpty)
        for interpreter in nonSystem {
            #expect(interpreter.isSystem == false)
        }
    }

    @Test("Intel homebrew prefix is discovered")
    func discoversIntelHomebrewPrefix() throws {
        let interpreters = try discover()
        let intel = try #require(interpreters.first { $0.executable.path.contains("/usr/local/opt") })
        #expect(intel.kind == .homebrew)
        #expect(intel.version == PythonInterpreter.PythonVersion(major: 3, minor: 12, patch: 0))
    }

    @Test("pythonExecutables filter excludes suffixed binaries like python3.12-config")
    func excludesSuffixedBinaries() throws {
        let interpreters = try discover()
        #expect(!interpreters.contains { $0.executable.path.hasSuffix("python3.12-config") })
        #expect(interpreters.contains { $0.executable.path.hasSuffix("python3.12") })
    }

    @Test("empty fixture filesystem returns no interpreters")
    func emptyFilesystem() {
        let provider = InMemoryDirectoryAccessProvider.make { _ in }
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/"),
            environment: .empty
        )

        #expect(discovery.discover().isEmpty)
    }

    @Test("opt symlink and Cellar target deduplicate to a single interpreter")
    func deduplicatesSymlinkedInterpreters() {
        // /opt/homebrew/opt/python@3.13/bin/python3.13 is a symlink to the Cellar binary.
        // Both paths appear as candidates from homebrewOptCandidates and homebrewCellarCandidates.
        // discover() must resolve symlinks before inserting into the seen set and return only one entry.
        let canonical = URL(fileURLWithPath: "/opt/homebrew/Cellar/python@3.13/3.13.2/bin/python3.13")
        let symlink = URL(fileURLWithPath: "/opt/homebrew/opt/python@3.13/bin/python3.13")

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: canonical, data: Data())
            builder.addSymlink(at: symlink, target: canonical)
        }

        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/"),
            environment: .empty
        )

        let interpreters = discovery.discover()
        #expect(interpreters.count == 1)
        // The opt candidate is processed first (homebrewOptCandidates before homebrewCellarCandidates).
        #expect(interpreters.first?.executable == symlink)
    }

    @Test("CORE25-012: a granted project root includes its own .venv")
    func grantedProjectRootIncludesOwnVenv() throws {
        let projectRoot = URL(fileURLWithPath: "/Users/tester/Code/installory-site")
        let venv = projectRoot.appendingPathComponent(".venv")
        let python = venv.appendingPathComponent("bin/python3")
        let sitePackages = venv.appendingPathComponent("lib/python3.12/site-packages")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: python, data: Data())
            builder.addFile(
                at: sitePackages.appendingPathComponent("example/__init__.py"),
                data: Data()
            )
        }
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/Users/tester"),
            environment: .empty,
            projectVenvRoots: [projectRoot]
        )

        let interpreter = try #require(
            discovery.discover().first { $0.kind == .projectVenv }
        )

        #expect(interpreter.executable == python)
        #expect(interpreter.version == .init(major: 3, minor: 12, patch: 0))
        #expect(interpreter.sitePackages == [sitePackages])
    }

    @Test("CORE-07: cancelled discovery does not walk or memoize a partial result")
    func cancelledDiscoveryDoesNotCachePartialResult() async throws {
        let python = URL(fileURLWithPath: "/Users/tester/.pyenv/versions/3.12.4/bin/python")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: python, data: Data())
        }
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/Users/tester"),
            environment: .empty
        )

        let cancelled = await Task { () -> [PythonInterpreter] in
            withUnsafeCurrentTask { $0?.cancel() }
            return discovery.discover()
        }.value
        let subsequent = discovery.discover()

        #expect(cancelled.isEmpty)
        #expect(subsequent.contains { $0.executable == python })
    }

    @Test("project venv discovery does not follow symlinks outside a granted root")
    func projectVenvSymlinkCannotEscapeGrantedRoot() {
        let grantedRoot = URL(fileURLWithPath: "/Users/tester/Code")
        let project = grantedRoot.appendingPathComponent("project")
        let externalVenv = URL(fileURLWithPath: "/Volumes/External/project-venv")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: externalVenv.appendingPathComponent("bin/python3"),
                data: Data()
            )
            builder.addFile(
                at: externalVenv.appendingPathComponent("lib/python3.12/site-packages/example.py"),
                data: Data()
            )
            builder.addSymlink(
                at: project.appendingPathComponent(".venv"),
                target: externalVenv
            )
        }
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/Users/tester"),
            environment: .empty,
            projectVenvRoots: [grantedRoot]
        )

        #expect(discovery.discover().allSatisfy { $0.kind != .projectVenv })
    }

    @Test("CORE-08: PYENV_ROOT overrides the default pyenv root")
    func pyenvRootOverridesDefaultRoot() throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let customPyenv = URL(fileURLWithPath: "/Volumes/Dev/pyenv")
        let customPython = customPyenv.appendingPathComponent("versions/3.12.4/bin/python")
        let defaultPython = home.appendingPathComponent(".pyenv/versions/3.11.9/bin/python")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: customPython, data: Data())
            builder.addFile(at: defaultPython, data: Data())
        }

        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: home,
            environment: PackageManagerEnvironment(values: ["PYENV_ROOT": customPyenv.path])
        )
        let pyenvInterpreters = discovery.discover().filter { $0.kind == .pyenv }

        #expect(pyenvInterpreters.map(\.executable) == [customPython])
        #expect(pyenvInterpreters.first?.version == .init(major: 3, minor: 12, patch: 4))
    }
}
