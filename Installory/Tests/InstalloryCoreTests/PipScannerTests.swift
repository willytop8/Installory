import Foundation
import Testing
@testable import InstalloryCore

@Suite("PipScanner")
struct PipScannerTests {
    // MARK: - Helpers

    private func buildProvider() throws -> InMemoryDirectoryAccessProvider {
        try FixtureResource.provider(
            directory: "python",
            mappedTo: URL(fileURLWithPath: "/")
        )
    }

    private func makeScanner(provider: any DirectoryAccessProvider) -> PipScanner {
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

    @Test("pip REQUESTED marker distinguishes direct installs from dependencies")
    func requestedMarkerControlsPipExplicitness() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        let requests = try #require(packages.first { $0.name == "requests" })
        let urllib3 = try #require(packages.first { $0.name == "urllib3" })
        let flask = try #require(packages.first { $0.name == "flask" })

        #expect(requests.isExplicit == true)
        #expect(flask.isExplicit == true)
        #expect(urllib3.isExplicit == false)
    }

    @Test("missing REQUESTED falls back to explicit for legacy and non-pip metadata")
    func missingRequestedUsesConservativeFallbackOutsidePip() async throws {
        let sitePackages = URL(
            fileURLWithPath: "/.pyenv/versions/3.11.0/lib/python3.11/site-packages"
        )
        let legacy = sitePackages.appendingPathComponent("legacy-tool-1.0.0.dist-info")
        let uv = sitePackages.appendingPathComponent("uv-tool-2.0.0.dist-info")

        func metadata(name: String, version: String) -> Data {
            Data("Metadata-Version: 2.1\nName: \(name)\nVersion: \(version)\n".utf8)
        }

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: URL(fileURLWithPath: "/.pyenv/versions/3.11.0/bin/python"),
                data: Data()
            )
            builder.addFile(
                at: legacy.appendingPathComponent("METADATA"),
                data: metadata(name: "legacy-tool", version: "1.0.0")
            )
            builder.addFile(
                at: uv.appendingPathComponent("METADATA"),
                data: metadata(name: "uv-tool", version: "2.0.0")
            )
            builder.addFile(
                at: uv.appendingPathComponent("INSTALLER"),
                data: Data("uv\n".utf8)
            )
        }

        let packages = try await makeScanner(provider: provider).scan()

        #expect(packages.first { $0.name == "legacy-tool" }?.isExplicit == true)
        #expect(packages.first { $0.name == "uv-tool" }?.isExplicit == true)
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

    // MARK: - CORE-05: RECORD-owned package sizes

    @Test("CORE-05: pip size sums unique RECORD files and excludes unrelated site-packages")
    func pipSizeUsesOnlyRecordOwnedFiles() async throws {
        let sitePackages = URL(
            fileURLWithPath: "/.pyenv/versions/3.11.0/lib/python3.11/site-packages"
        )
        let distInfo = sitePackages.appendingPathComponent("owned-1.0.0.dist-info")
        let metadata = "Metadata-Version: 2.1\nName: owned\nVersion: 1.0.0\n"
        let record = """
            owned/__init__.py,,
            owned/data.bin,,
            owned/data.bin,,
            owned-1.0.0.dist-info/METADATA,,
            owned-1.0.0.dist-info/RECORD,,
            """
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: URL(fileURLWithPath: "/.pyenv/versions/3.11.0/bin/python"),
                data: Data()
            )
            builder.addFile(
                at: sitePackages.appendingPathComponent("owned/__init__.py"),
                data: Data(),
                logicalSizeBytes: 20
            )
            builder.addFile(
                at: sitePackages.appendingPathComponent("owned/data.bin"),
                data: Data(),
                logicalSizeBytes: 30
            )
            builder.addFile(
                at: distInfo.appendingPathComponent("METADATA"),
                data: Data(metadata.utf8),
                logicalSizeBytes: 11
            )
            builder.addFile(
                at: distInfo.appendingPathComponent("RECORD"),
                data: Data(record.utf8),
                logicalSizeBytes: 13
            )
            builder.addFile(
                at: sitePackages.appendingPathComponent("unrelated/huge.bin"),
                data: Data(),
                logicalSizeBytes: 999_999
            )
        }

        let package = try #require(try await makeScanner(provider: provider).scan().first)

        #expect(package.name == "owned")
        #expect(package.sizeBytes == 74)
    }

    @Test("PERF25-011: oversized RECORD stays unread and makes pip size unknown")
    func oversizedRecordIsNotLoaded() async throws {
        let root = URL(fileURLWithPath: "/.pyenv/versions/3.11.0")
        let sitePackages = root.appendingPathComponent("lib/python3.11/site-packages")
        let distInfo = sitePackages.appendingPathComponent("large-record-1.0.0.dist-info")
        let record = distInfo.appendingPathComponent("RECORD")
        let base = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("bin/python"), data: Data())
            builder.addFile(
                at: distInfo.appendingPathComponent("METADATA"),
                data: Data(
                    "Metadata-Version: 2.1\nName: large-record\nVersion: 1.0.0\n".utf8
                )
            )
            builder.addFile(
                at: record,
                data: Data("large_record/__init__.py,,\n".utf8),
                logicalSizeBytes: Int64.max
            )
            builder.addFile(
                at: sitePackages.appendingPathComponent("large_record/__init__.py"),
                data: Data(),
                logicalSizeBytes: 99
            )
        }
        let trace = DirectoryAccessTrace()
        let provider = TracingDirectoryAccessProvider(base: base, trace: trace)

        let package = try #require(try await makeScanner(provider: provider).scan().first)

        #expect(package.name == "large-record")
        #expect(package.sizeBytes == nil)
        #expect(trace.entries.contains { $0.operation == .metadata && $0.url.path == record.path })
        #expect(!trace.entries.contains { $0.operation == .data && $0.url.path == record.path })
    }

    @Test("PERF25-011: oversized INSTALLER stays unread")
    func oversizedInstallerIsNotLoaded() async throws {
        let root = URL(fileURLWithPath: "/.pyenv/versions/3.11.0")
        let sitePackages = root.appendingPathComponent("lib/python3.11/site-packages")
        let distInfo = sitePackages.appendingPathComponent("bounded-1.0.0.dist-info")
        let installer = distInfo.appendingPathComponent("INSTALLER")
        let base = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("bin/python"), data: Data())
            builder.addFile(
                at: distInfo.appendingPathComponent("METADATA"),
                data: Data("Metadata-Version: 2.1\nName: bounded\nVersion: 1.0.0\n".utf8)
            )
            builder.addFile(
                at: installer,
                data: Data("pip\n".utf8),
                logicalSizeBytes: Int64.max
            )
        }
        let trace = DirectoryAccessTrace()
        let provider = TracingDirectoryAccessProvider(base: base, trace: trace)

        let package = try #require(try await makeScanner(provider: provider).scan().first)

        #expect(package.name == "bounded")
        #expect(package.isExplicit)
        #expect(trace.entries.contains { $0.operation == .metadata && $0.url.path == installer.path })
        #expect(!trace.entries.contains { $0.operation == .data && $0.url.path == installer.path })
    }

    @Test("CORE-05: pip rejects absolute RECORD paths before sizing")
    func pipRejectsAbsoluteRecordPath() async throws {
        try await assertUnsafeRecordPath("/outside.bin")
    }

    @Test("CORE-05: pip rejects RECORD paths escaping the interpreter root")
    func pipRejectsEscapingRecordPath() async throws {
        try await assertUnsafeRecordPath("../../../../outside.bin")
    }

    @Test("CORE-05: pip rejects RECORD paths escaping through a parent symlink")
    func pipRejectsRecordPathThroughParentSymlink() async throws {
        let root = URL(fileURLWithPath: "/.pyenv/versions/3.11.0")
        let sitePackages = root.appendingPathComponent("lib/python3.11/site-packages")
        let distInfo = sitePackages.appendingPathComponent("unsafe-1.0.0.dist-info")
        let linkedDirectory = sitePackages.appendingPathComponent("unsafe")
        let outside = URL(fileURLWithPath: "/outside")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("bin/python"), data: Data())
            builder.addFile(
                at: distInfo.appendingPathComponent("METADATA"),
                data: Data("Metadata-Version: 2.1\nName: unsafe\nVersion: 1.0.0\n".utf8)
            )
            builder.addFile(
                at: distInfo.appendingPathComponent("RECORD"),
                data: Data("unsafe/payload.bin,,\n".utf8)
            )
            builder.addSymlink(at: linkedDirectory, target: outside)
            builder.addFile(
                at: outside.appendingPathComponent("payload.bin"),
                data: Data(),
                logicalSizeBytes: 999
            )
        }

        let package = try #require(try await makeScanner(provider: provider).scan().first)

        #expect(package.sizeBytes == nil)
    }

    @Test("CORE-05: pip scanning propagates task cancellation")
    func pipScanningPropagatesCancellation() async throws {
        let provider = try buildProvider()
        let scanner = makeScanner(provider: provider)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    private func assertUnsafeRecordPath(_ unsafePath: String) async throws {
        let sitePackages = URL(
            fileURLWithPath: "/.pyenv/versions/3.11.0/lib/python3.11/site-packages"
        )
        let distInfo = sitePackages.appendingPathComponent("unsafe-1.0.0.dist-info")
        let metadata = "Metadata-Version: 2.1\nName: unsafe\nVersion: 1.0.0\n"
        let record = "owned.py,,\n\(unsafePath),,\n"
        let escapedURL = unsafePath.hasPrefix("/")
            ? URL(fileURLWithPath: unsafePath)
            : sitePackages.appendingPathComponent(unsafePath).standardizedFileURL
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: URL(fileURLWithPath: "/.pyenv/versions/3.11.0/bin/python"),
                data: Data()
            )
            builder.addFile(at: distInfo.appendingPathComponent("METADATA"), data: Data(metadata.utf8))
            builder.addFile(at: distInfo.appendingPathComponent("RECORD"), data: Data(record.utf8))
            builder.addFile(
                at: sitePackages.appendingPathComponent("owned.py"),
                data: Data(),
                logicalSizeBytes: 10
            )
            builder.addFile(at: escapedURL, data: Data(), logicalSizeBytes: 999)
        }

        let package = try #require(try await makeScanner(provider: provider).scan().first)

        #expect(package.sizeBytes == nil)
    }
}
