import Foundation
import Testing
@testable import InstalloryCore

@Suite("PipxScanner")
struct PipxScannerTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test("reports the main pipx tool, not its venv dependencies")
    func reportsMainToolOnly() async throws {
        let blackVenv = home.appendingPathComponent(".local/share/pipx/venvs/black")
        let sitePackages = blackVenv.appendingPathComponent("lib/python3.12/site-packages")
        let blackDist = sitePackages.appendingPathComponent("black-24.4.2.dist-info")
        let clickDist = sitePackages.appendingPathComponent("click-8.1.7.dist-info")

        let blackMetadata = """
            Metadata-Version: 2.1
            Name: black
            Version: 24.4.2
            Requires-Dist: click (>=8.0)
            """
        let clickMetadata = """
            Metadata-Version: 2.1
            Name: click
            Version: 8.1.7
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
            builder.addFile(at: blackDist.appendingPathComponent("METADATA"), data: Data(blackMetadata.utf8))
            builder.addFile(at: clickDist.appendingPathComponent("METADATA"), data: Data(clickMetadata.utf8))
            builder.addFile(at: blackVenv.appendingPathComponent("pipx_metadata.json"), data: Data(pipxMetadata.utf8))
        }

        let packages = try await PipxScanner(directoryAccess: provider, homeDirectory: home).scan()

        #expect(packages.count == 1)
        let black = try #require(packages.first)
        #expect(black.id == "pipx::black")
        #expect(black.manager == .pipx)
        #expect(black.name == "black")
        #expect(black.version == "24.4.2")
        #expect(black.installPath?.path == blackVenv.path)
        #expect(black.dependencies == ["click"])
        #expect(black.isReadOnly == false)
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
}
