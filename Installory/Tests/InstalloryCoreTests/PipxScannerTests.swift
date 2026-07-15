import Foundation
import Testing
@testable import InstalloryCore

@Suite("PipxScanner")
struct PipxScannerTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test("TEST25-009: pipx metadata selects the main dist-info fixture")
    func reportsMainToolOnly() async throws {
        let venv = home.appendingPathComponent(".local/share/pipx/venvs/fixture-tool")
        let provider = try FixtureResource.provider(
            directory: "pipx/with-dist-info",
            mappedTo: venv
        )

        let packages = try await PipxScanner(directoryAccess: provider, homeDirectory: home).scan()

        #expect(packages.count == 1)
        let package = try #require(packages.first)
        #expect(package.id == "pipx:\(venv.path):fixture-tool")
        #expect(package.manager == .pipx)
        #expect(package.qualifier == venv.path)
        #expect(package.name == "fixture-tool")
        #expect(package.version == "2.3.1")
        #expect(package.installPath?.path == venv.path)
        #expect(package.dependencies == ["fixture-dependency"])
        #expect(package.isReadOnly == false)
    }

    @Test("falls back to matching the venv directory name")
    func fallsBackToToolDirectoryName() async throws {
        let venv = home.appendingPathComponent(".local/share/pipx/venvs/httpie")
        let sitePackages = venv.appendingPathComponent("lib/python3.11/site-packages")
        let dist = sitePackages.appendingPathComponent("httpie-3.2.2.dist-info")
        let metadata = """
            Metadata-Version: 2.1
            Name: httpie
            Version: 3.2.2
            """

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: dist.appendingPathComponent("METADATA"), data: Data(metadata.utf8))
        }

        let packages = try await PipxScanner(directoryAccess: provider, homeDirectory: home).scan()

        #expect(packages.map(\.name) == ["httpie"])
    }

    @Test("availability follows the pipx venvs root")
    func availabilityFollowsVenvRoot() async throws {
        let missing = InMemoryDirectoryAccessProvider.make { _ in }
        #expect(await PipxScanner(directoryAccess: missing, homeDirectory: home).isAvailable() == false)

        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".local/share/pipx/venvs/black/pyvenv.cfg"),
                data: Data()
            )
        }
        #expect(await PipxScanner(directoryAccess: present, homeDirectory: home).isAvailable() == true)
    }

    @Test("CORE-08: PIPX_HOME relocates pipx discovery")
    func pipxHomeRelocatesDiscovery() async throws {
        let pipxHome = URL(fileURLWithPath: "/Volumes/Dev/pipx", isDirectory: true)
        let venv = pipxHome.appendingPathComponent("venvs/ruff", isDirectory: true)
        let metadata = #"{"main_package":{"package":"ruff","package_version":"0.5.0"}}"#
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: venv.appendingPathComponent("pipx_metadata.json"),
                data: Data(metadata.utf8)
            )
        }
        let scanner = PipxScanner(
            directoryAccess: provider,
            homeDirectory: home,
            environment: PackageManagerEnvironment(values: ["PIPX_HOME": pipxHome.path])
        )

        #expect(await scanner.isAvailable())
        let package = try #require(try await scanner.scan().first)
        #expect(package.name == "ruff")
        #expect(package.qualifier == venv.path)
    }

    @Test("CORE-05: pipx size includes the entire venv tree")
    func sizeIncludesEntireVenvTree() async throws {
        let venv = home.appendingPathComponent(".local/share/pipx/venvs/ruff")
        let dist = venv.appendingPathComponent(
            "lib/python3.12/site-packages/ruff-0.5.0.dist-info"
        )
        let metadata = """
            Metadata-Version: 2.1
            Name: ruff
            Version: 0.5.0
            """
        let pipxMetadata = """
            {
              "main_package": {
                "package": "ruff",
                "package_version": "0.5.0"
              }
            }
            """

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: dist.appendingPathComponent("METADATA"),
                data: Data(metadata.utf8),
                logicalSizeBytes: 10
            )
            builder.addFile(
                at: venv.appendingPathComponent("pipx_metadata.json"),
                data: Data(pipxMetadata.utf8),
                logicalSizeBytes: 20
            )
            builder.addFile(
                at: venv.appendingPathComponent("bin/ruff"),
                data: Data(),
                logicalSizeBytes: 30
            )
            builder.addFile(
                at: venv.appendingPathComponent("lib/python3.12/site-packages/anyio/core.py"),
                data: Data(),
                logicalSizeBytes: 7
            )
        }

        let packages = try await PipxScanner(
            directoryAccess: provider,
            homeDirectory: home
        ).scan()
        let ruff = try #require(packages.first)

        #expect(ruff.sizeBytes == 67)
    }

    @Test("CORE25-016/TEST25-009: metadata fixture survives missing dist-info")
    func metadataOnlyVenvIsInventoried() async throws {
        let venv = home.appendingPathComponent(
            ".local/share/pipx/venvs/fixture-metadata-only-suffix"
        )
        let provider = try FixtureResource.provider(
            directory: "pipx/metadata-only",
            mappedTo: venv
        )

        let packages = try await PipxScanner(
            directoryAccess: provider,
            homeDirectory: home
        ).scan()
        let package = try #require(packages.first)

        #expect(package.id == "pipx:\(venv.path):fixture-metadata-only")
        #expect(package.qualifier == venv.path)
        #expect(package.name == "fixture-metadata-only")
        #expect(package.version == "1.8.3")
        #expect(package.dependencies.isEmpty)
        #expect((package.sizeBytes ?? 0) > 0)
    }

    @Test("CORE-05: pipx scan cancellation propagates")
    func cancellationPropagates() async {
        let venv = home.appendingPathComponent(".local/share/pipx/venvs/black")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: venv.appendingPathComponent("pipx_metadata.json"),
                data: Data(#"{"main_package":{"package":"black","package_version":"24.4.2"}}"#.utf8)
            )
        }
        let scanner = PipxScanner(directoryAccess: provider, homeDirectory: home)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("CORE25-004: suffixed pipx venvs keep distinct stable identities and qualifiers")
    func suffixedVenvsKeepDistinctStableIdentities() async throws {
        // These mirror `pipx install black --suffix=-3-11` and `--suffix=-3-12`.
        // The installed distribution metadata is intentionally identical; only
        // the pipx-managed environment directories distinguish the two installs.
        let venv311 = home.appendingPathComponent(".local/share/pipx/venvs/black-3-11")
        let venv312 = home.appendingPathComponent(".local/share/pipx/venvs/black-3-12")
        let distRelativePath = "lib/python3.12/site-packages/black-24.4.2.dist-info/METADATA"
        let distributionMetadata = """
            Metadata-Version: 2.1
            Name: black
            Version: 24.4.2
            """
        let pipxMetadata = """
            {
              "main_package": {
                "package": "black",
                "package_version": "24.4.2"
              }
            }
            """

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            for venv in [venv311, venv312] {
                builder.addFile(
                    at: venv.appendingPathComponent(distRelativePath),
                    data: Data(distributionMetadata.utf8)
                )
                builder.addFile(
                    at: venv.appendingPathComponent("pipx_metadata.json"),
                    data: Data(pipxMetadata.utf8)
                )
            }
        }
        let scanner = PipxScanner(directoryAccess: provider, homeDirectory: home)

        let firstScan = try await scanner.scan()
        let secondScan = try await scanner.scan()
        let expectedIDs: Set<String> = [
            "pipx:\(venv311.path):black",
            "pipx:\(venv312.path):black",
        ]

        #expect(firstScan.count == 2)
        #expect(firstScan.allSatisfy { $0.name == "black" })
        #expect(Set(firstScan.map(\.id)) == expectedIDs)
        #expect(Set(firstScan.compactMap(\.qualifier)) == [venv311.path, venv312.path])
        #expect(Dictionary(grouping: firstScan, by: \.id).count == 2)
        #expect(secondScan.map(\.id) == firstScan.map(\.id))
        #expect(secondScan.map(\.qualifier) == firstScan.map(\.qualifier))
    }
}
