import Foundation
import Testing
@testable import InstalloryCore

@Suite("PythonInterpreterDiscovery")
struct PythonInterpreterDiscoveryTests {
    private static let fixtureDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/python")

    private func buildProvider() throws -> InMemoryDirectoryAccessProvider {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Self.fixtureDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return InMemoryDirectoryAccessProvider.make { builder in
            while let fileURL = enumerator.nextObject() as? URL {
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isFile else { continue }

                let relativePath = String(fileURL.path.dropFirst(Self.fixtureDir.path.count))
                let fakeURL = URL(fileURLWithPath: relativePath)
                if let data = try? Data(contentsOf: fileURL) {
                    builder.addFile(at: fakeURL, data: data)
                }
            }
        }
    }

    private func discover() throws -> [PythonInterpreter] {
        let provider = try buildProvider()
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/")
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
            homeDirectory: URL(fileURLWithPath: "/")
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
            homeDirectory: URL(fileURLWithPath: "/")
        )

        let interpreters = discovery.discover()
        #expect(interpreters.count == 1)
        // The opt candidate is processed first (homebrewOptCandidates before homebrewCellarCandidates).
        #expect(interpreters.first?.executable == symlink)
    }
}
