import Foundation
import Testing
@testable import InstalloryCore

@Suite("CargoScanner")
struct CargoScannerTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func scanner(
        provider: any DirectoryAccessProvider,
        environment: PackageManagerEnvironment = .empty
    ) -> CargoScanner {
        CargoScanner(
            directoryAccess: provider,
            homeDirectory: home,
            environment: environment
        )
    }

    @Test("TEST25-009: reads an authentic-shape Cargo .crates2.json resource")
    func readsCargoInstallMetadata() async throws {
        let cargoHome = home.appendingPathComponent(".cargo")
        let fixtureBin = cargoHome.appendingPathComponent("bin/fixture-cli")
        let installedAt = Date(timeIntervalSince1970: 1_715_000_000)
        let provider = try FixtureResource.provider(
            directory: "cargo",
            mappedTo: cargoHome,
            modificationDate: installedAt
        )

        let packages = try await scanner(provider: provider).scan()

        #expect(packages.map(\.name) == ["fixture-cli"])

        let package = try #require(packages.first)
        #expect(package.id == "cargo::fixture-cli")
        #expect(package.manager == .cargo)
        #expect(package.qualifier == "registry+https://github.com/rust-lang/crates.io-index")
        #expect(package.version == "1.4.2")
        #expect(package.installPath == fixtureBin)
        #expect(package.installedAt == installedAt)
        #expect(package.installedAtConfidence == .medium)
        #expect(package.dependencies.isEmpty)
        #expect((package.sizeBytes ?? 0) > 0)
    }

    @Test("CORE25-009: Cargo scanner preserves registry, git, and path sources")
    func preservesRecordedInstallSources() async throws {
        let metadata = """
            {
              "installs": {
                "registry-tool 1.0.0 (registry+sparse+https://cargo.example/index/)": {
                  "bins": ["registry-tool"]
                },
                "git-tool 2.0.0 (git+https://github.com/example/tools?branch=stable#0123456789abcdef)": {
                  "bins": ["git-tool"]
                },
                "path-tool 3.0.0 (path+file:///Users/tester/Code/path-tool)": {
                  "bins": ["path-tool"]
                }
              }
            }
            """
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".cargo/.crates2.json"),
                data: Data(metadata.utf8)
            )
        }

        let packages = try await scanner(provider: provider).scan()
        let sources = Dictionary(uniqueKeysWithValues: packages.map { ($0.name, $0.qualifier) })

        #expect(sources["registry-tool"] == "registry+sparse+https://cargo.example/index/")
        #expect(sources["git-tool"] == "git+https://github.com/example/tools?branch=stable#0123456789abcdef")
        #expect(sources["path-tool"] == "path+file:///Users/tester/Code/path-tool")
    }

    @Test("CORE25-001: malformed cargo metadata fails instead of reporting an empty inventory")
    func malformedMetadataFailsScan() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".cargo/.crates2.json"),
                data: Data("{not json".utf8)
            )
        }

        do {
            _ = try await scanner(provider: provider).scan()
            Issue.record("malformed metadata must fail so cached Cargo packages are preserved")
        } catch is DecodingError {
            // Expected: ScanCoordinator converts this into `.failed`.
        }
    }

    @Test("availability follows .crates2.json")
    func availabilityFollowsCratesFile() async throws {
        let missing = InMemoryDirectoryAccessProvider.make { _ in }
        #expect(await scanner(provider: missing).isAvailable() == false)

        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: home.appendingPathComponent(".cargo/.crates2.json"), data: Data("{}".utf8))
        }
        #expect(await scanner(provider: present).isAvailable() == true)
    }

    @Test("CORE-08: CARGO_HOME overrides the default Cargo metadata and bin roots")
    func cargoHomeOverridesDefaultRoot() async throws {
        let customHome = URL(fileURLWithPath: "/Volumes/Dev/cargo")
        let defaultMetadata = #"{"installs":{"fallback 1.0.0":{"bins":["fallback"]}}}"#
        let customMetadata = #"{"installs":{"custom 2.0.0":{"bins":["custom"]}}}"#
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".cargo/.crates2.json"),
                data: Data(defaultMetadata.utf8)
            )
            builder.addFile(
                at: customHome.appendingPathComponent(".crates2.json"),
                data: Data(customMetadata.utf8)
            )
            builder.addFile(
                at: customHome.appendingPathComponent("bin/custom"),
                data: Data()
            )
        }

        let packages = try await scanner(
            provider: provider,
            environment: PackageManagerEnvironment(values: ["CARGO_HOME": customHome.path])
        ).scan()

        #expect(packages.map(\.name) == ["custom"])
        #expect(packages.first?.installPath == customHome.appendingPathComponent("bin/custom"))
    }

    @Test("CORE-05: Cargo sums every declared binary's exact logical size")
    func cargoSumsEveryDeclaredBinary() async throws {
        let cargoHome = home.appendingPathComponent(".cargo")
        let metadata = #"{"installs":{"cargo-edit 0.13.0":{"bins":["cargo-rm","cargo-add"]}}}"#
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: cargoHome.appendingPathComponent(".crates2.json"),
                data: Data(metadata.utf8)
            )
            builder.addFile(
                at: cargoHome.appendingPathComponent("bin/cargo-add"),
                data: Data(),
                logicalSizeBytes: 41
            )
            builder.addFile(
                at: cargoHome.appendingPathComponent("bin/cargo-rm"),
                data: Data(),
                logicalSizeBytes: 67
            )
        }

        let package = try #require(try await scanner(provider: provider).scan().first)

        #expect(package.name == "cargo-edit")
        #expect(package.sizeBytes == 108)
    }

    @Test("CORE-05: an unsafe Cargo bin path is never accessed and yields unknown size")
    func unsafeCargoBinPathIsNeverAccessed() async throws {
        let cargoHome = home.appendingPathComponent(".cargo")
        let metadata = #"{"installs":{"hostile 1.0.0":{"bins":["../escape","safe"]}}}"#
        let base = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: cargoHome.appendingPathComponent(".crates2.json"),
                data: Data(metadata.utf8)
            )
            builder.addFile(
                at: cargoHome.appendingPathComponent("bin/safe"),
                data: Data(),
                logicalSizeBytes: 12
            )
            builder.addFile(
                at: cargoHome.appendingPathComponent("escape"),
                data: Data(),
                logicalSizeBytes: 9_999
            )
        }
        let accessLog = DirectoryAccessLog()
        let provider = RecordingDirectoryAccessProvider(base: base, log: accessLog)

        let package = try #require(try await scanner(provider: provider).scan().first)

        #expect(package.sizeBytes == nil)
        #expect(package.installPath == cargoHome)
        #expect(!accessLog.paths.contains { $0.contains("escape") })
    }

    @Test("CORE-05: Cargo scanning propagates task cancellation")
    func cargoScanningPropagatesCancellation() async {
        let metadata = #"{"installs":{"ripgrep 14.1.0":{"bins":["rg"]}}}"#
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".cargo/.crates2.json"),
                data: Data(metadata.utf8)
            )
        }
        let scanner = scanner(provider: provider)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

private final class DirectoryAccessLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPaths: [String] = []

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths
    }

    func record(_ url: URL) {
        lock.lock()
        storedPaths.append(url.path)
        lock.unlock()
    }
}

private struct RecordingDirectoryAccessProvider: DirectoryAccessProvider, Sendable {
    let base: InMemoryDirectoryAccessProvider
    let log: DirectoryAccessLog

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        log.record(url)
        return try base.contentsOfDirectory(at: url)
    }

    func data(contentsOf url: URL) throws -> Data {
        log.record(url)
        return try base.data(contentsOf: url)
    }

    func fileExists(at url: URL) -> Bool {
        log.record(url)
        return base.fileExists(at: url)
    }

    func modificationDate(at url: URL) -> Date? {
        log.record(url)
        return base.modificationDate(at: url)
    }

    func metadata(at url: URL) throws -> FileSystemItemMetadata {
        log.record(url)
        return try base.metadata(at: url)
    }

    func resolvingSymlinks(at url: URL) -> URL {
        log.record(url)
        return base.resolvingSymlinks(at: url)
    }
}
