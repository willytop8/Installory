import Foundation
import Testing
@testable import BackshelfCore

@Suite("PipScanner")
struct PipScannerTests {
    private static let fixtureDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/python")

    // MARK: - Helpers

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

    private func makeScanner(provider: InMemoryDirectoryAccessProvider) -> PipScanner {
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/")
        )
        let parser = DistInfoParser(directoryAccess: provider)
        return PipScanner(discovery: discovery, parser: parser, directoryAccess: provider)
    }

    // MARK: - Tests

    @Test("discovers all packages across all fixture interpreters")
    func discoversAllPackages() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        // pyenv 3.11.7: requests + urllib3 (2 packages)
        // homebrew 3.12: flask (1 package)
        // system + intel homebrew have no site-packages in fixture
        #expect(packages.count == 3)
        #expect(packages.contains { $0.name == "requests" })
        #expect(packages.contains { $0.name == "urllib3" })
        #expect(packages.contains { $0.name == "flask" })
    }

    @Test("each Package.id matches documented format")
    func packageIdFormat() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        let requests = try #require(packages.first { $0.name == "requests" })
        let flask = try #require(packages.first { $0.name == "flask" })

        #expect(requests.id == "pip:/.pyenv/versions/3.11.7/bin/python:requests")
        #expect(flask.id == "pip:/opt/homebrew/opt/python@3.12/bin/python3.12:flask")
    }

    @Test("qualifier matches interpreter executable path")
    func qualifierMatchesInterpreterPath() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        for package in packages {
            let qualifier = try #require(package.qualifier)
            #expect(package.id.hasPrefix("pip:\(qualifier):"))
        }
    }

    @Test("all packages have manager=.pip")
    func allPackagesHavePipManager() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        for package in packages {
            #expect(package.manager == .pip)
        }
    }

    @Test("pyenv and homebrew packages are not read-only")
    func nonSystemPackagesAreWritable() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        // All fixture packages come from pyenv or homebrew — none are system
        for package in packages {
            #expect(package.isReadOnly == false)
        }
    }

    @Test("system Python packages have isReadOnly=true")
    func systemPackagesAreReadOnly() async throws {
        let sitePackages = URL(fileURLWithPath: "/usr/lib/python3.11/site-packages")
        let distInfo = sitePackages.appendingPathComponent("six-1.16.0.dist-info")

        let metadata = """
            Metadata-Version: 2.1
            Name: six
            Version: 1.16.0
            Summary: Python 2 and 3 compatibility utilities
            License: MIT
            """

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: URL(fileURLWithPath: "/usr/bin/python3"), data: Data())
            builder.addFile(at: distInfo.appendingPathComponent("METADATA"), data: Data(metadata.utf8))
            builder.addFile(at: distInfo.appendingPathComponent("RECORD"), data: Data())
        }

        let packages = try await makeScanner(provider: provider).scan()

        #expect(packages.count == 1)
        let six = try #require(packages.first)
        #expect(six.name == "six")
        #expect(six.isReadOnly == true)
        #expect(six.id == "pip:/usr/bin/python3:six")
    }

    @Test("Requires-Dist stripped to bare names with version constraints and environment markers removed")
    func dependenciesStrippedToBareNames() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        let requests = try #require(packages.first { $0.name == "requests" })

        // Fixture METADATA has:
        //   Requires-Dist: charset-normalizer (>=2,<4)
        //   Requires-Dist: idna (>=2.5,<4)
        //   Requires-Dist: urllib3 (>=1.21.1,<3); python_version >= '3.8'
        //   Requires-Dist: certifi (>=2017.4.17)
        #expect(Set(requests.dependencies) == ["charset-normalizer", "idna", "urllib3", "certifi"])
    }

    @Test("packages with no Requires-Dist have empty dependencies")
    func noRequiresDistGivesEmptyDeps() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        // urllib3 fixture METADATA has no Requires-Dist
        let urllib3 = try #require(packages.first { $0.name == "urllib3" })
        #expect(urllib3.dependencies.isEmpty)
    }

    @Test("installedAtConfidence is medium for all pip packages")
    func installedAtConfidenceIsMedium() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        for package in packages {
            #expect(package.installedAtConfidence == .medium)
        }
    }

    @Test("installPath points to the dist-info directory")
    func installPathIsDistInfoDirectory() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        for package in packages {
            let installPath = try #require(package.installPath)
            #expect(installPath.lastPathComponent.hasSuffix(".dist-info"))
        }
    }

    @Test("isExplicit is true for all pip packages")
    func isExplicitAlwaysTrue() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        for package in packages {
            #expect(package.isExplicit == true)
        }
    }

    @Test("same package in multiple interpreters produces distinct rows")
    func samePackageInMultipleInterpretersIsDistinct() async throws {
        // Use /.pyenv/... so PythonInterpreterDiscovery (homeDirectory: /) can find them
        let siteA = URL(fileURLWithPath: "/.pyenv/versions/3.11.0/lib/python3.11/site-packages")
        let siteB = URL(fileURLWithPath: "/.pyenv/versions/3.12.0/lib/python3.12/site-packages")
        let distA = siteA.appendingPathComponent("requests-2.31.0.dist-info")
        let distB = siteB.appendingPathComponent("requests-2.31.0.dist-info")

        let metadata = "Metadata-Version: 2.1\nName: requests\nVersion: 2.31.0\n"

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: URL(fileURLWithPath: "/.pyenv/versions/3.11.0/bin/python"), data: Data())
            builder.addFile(at: URL(fileURLWithPath: "/.pyenv/versions/3.12.0/bin/python"), data: Data())
            builder.addFile(at: distA.appendingPathComponent("METADATA"), data: Data(metadata.utf8))
            builder.addFile(at: distB.appendingPathComponent("METADATA"), data: Data(metadata.utf8))
        }

        let packages = try await makeScanner(provider: provider).scan()

        #expect(packages.count == 2)
        #expect(packages[0].id != packages[1].id)
        #expect(packages.allSatisfy { $0.name == "requests" })
    }

    @Test("empty interpreter list returns empty package list")
    func emptyInterpretersReturnsEmpty() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { _ in }
        let packages = try await makeScanner(provider: provider).scan()
        #expect(packages.isEmpty)
    }

    @Test("symlinked interpreter emits each package ID exactly once")
    func symlinkedInterpreterEmitsUniqueIds() async throws {
        // /opt/homebrew/opt/python@3.13/bin/python3.13 (symlink) and
        // /opt/homebrew/Cellar/python@3.13/3.13.2/bin/python3.13 (canonical) both appear
        // as discovery candidates. After Layer 1 dedup (resolved path), only one interpreter
        // is returned. Layer 2 in PipScanner catches any that slip through. Verify no
        // duplicate Package IDs reach the caller.
        let canonical = URL(fileURLWithPath: "/opt/homebrew/Cellar/python@3.13/3.13.2/bin/python3.13")
        let symlink = URL(fileURLWithPath: "/opt/homebrew/opt/python@3.13/bin/python3.13")
        let sitePackages = URL(fileURLWithPath: "/opt/homebrew/opt/python@3.13/lib/python3.13/site-packages")
        let distInfo = sitePackages.appendingPathComponent("pip-24.0.dist-info")
        let metadata = "Metadata-Version: 2.1\nName: pip\nVersion: 24.0\n"

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: canonical, data: Data())
            builder.addSymlink(at: symlink, target: canonical)
            builder.addFile(at: distInfo.appendingPathComponent("METADATA"), data: Data(metadata.utf8))
            builder.addFile(at: distInfo.appendingPathComponent("RECORD"), data: Data())
        }

        let packages = try await makeScanner(provider: provider).scan()

        let ids = packages.map(\.id)
        #expect(Set(ids).count == ids.count, "Package IDs must be unique; got duplicates: \(ids)")
        #expect(packages.count == 1)
        #expect(packages.first?.name == "pip")
    }

    @Test("interpreter with no site-packages does not crash and returns no packages")
    func missingSitePackagesDoesNotCrash() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        // The fixture system Python (/usr/bin/python3) has no site-packages directory.
        // Verify the scan completes and produces no packages attributed to it.
        let systemPackages = packages.filter { $0.qualifier == "/usr/bin/python3" }
        #expect(systemPackages.isEmpty)
    }
}
