import Foundation
import Testing
@testable import InstalloryCore

@Suite("CargoScanner")
struct CargoScannerTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test("reads cargo install metadata from .crates2.json")
    func readsCargoInstallMetadata() async throws {
        let cargoHome = home.appendingPathComponent(".cargo")
        let cratesFile = cargoHome.appendingPathComponent(".crates2.json")
        let rgBin = cargoHome.appendingPathComponent("bin/rg")
        let installedAt = Date(timeIntervalSince1970: 1_715_000_000)
        let metadata = """
            {
              "installs": {
                "ripgrep 14.1.0 (registry+https://github.com/rust-lang/crates.io-index)": {
                  "bins": ["rg"]
                },
                "cargo-edit 0.13.0 (registry+https://github.com/rust-lang/crates.io-index)": {
                  "bins": ["cargo-add", "cargo-rm", "cargo-set-version", "cargo-upgrade"]
                }
              }
            }
            """

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: cratesFile, data: Data(metadata.utf8))
            builder.addFile(at: rgBin, data: Data(), modificationDate: installedAt)
        }

        let packages = try await CargoScanner(directoryAccess: provider, homeDirectory: home).scan()

        #expect(packages.map(\.name) == ["cargo-edit", "ripgrep"])

        let ripgrep = try #require(packages.first { $0.name == "ripgrep" })
        #expect(ripgrep.id == "cargo::ripgrep")
        #expect(ripgrep.manager == .cargo)
        #expect(ripgrep.version == "14.1.0")
        #expect(ripgrep.installPath == rgBin)
        #expect(ripgrep.installedAt == installedAt)
        #expect(ripgrep.installedAtConfidence == .medium)
        #expect(ripgrep.dependencies.isEmpty)
    }

    @Test("malformed cargo metadata yields no packages")
    func malformedMetadataYieldsNoPackages() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".cargo/.crates2.json"),
                data: Data("{not json".utf8)
            )
        }

        let packages = try await CargoScanner(directoryAccess: provider, homeDirectory: home).scan()
        #expect(packages.isEmpty)
    }

    @Test("availability follows .crates2.json")
    func availabilityFollowsCratesFile() async throws {
        let missing = InMemoryDirectoryAccessProvider.make { _ in }
        #expect(await CargoScanner(directoryAccess: missing, homeDirectory: home).isAvailable() == false)

        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: home.appendingPathComponent(".cargo/.crates2.json"), data: Data("{}".utf8))
        }
        #expect(await CargoScanner(directoryAccess: present, homeDirectory: home).isAvailable() == true)
    }
}
