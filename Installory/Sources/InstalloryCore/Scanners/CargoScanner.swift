import Foundation

/// Scans binaries installed by `cargo install` by reading Cargo's
/// `~/.cargo/.crates2.json` metadata file.
///
/// No `cargo` invocation is made.
public struct CargoScanner: PackageScanner, Sendable {
    public let manager: PackageManager = .cargo

    private let directoryAccess: any DirectoryAccessProvider
    private let homeDirectory: URL

    public init(
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.directoryAccess = directoryAccess
        self.homeDirectory = homeDirectory
    }

    public func isAvailable() async -> Bool {
        directoryAccess.fileExists(at: cratesFile)
    }

    public var unavailableReason: String {
        "Cargo install metadata not granted or not found"
    }

    public func scan() async throws -> [Package] {
        guard let data = try? directoryAccess.data(contentsOf: cratesFile),
              let metadata = try? JSONDecoder().decode(CargoCratesMetadata.self, from: data) else {
            return []
        }

        return metadata.installs
            .compactMap(makePackage(key:install:))
            .sorted { $0.name < $1.name }
    }

    private var cargoHome: URL {
        homeDirectory.appendingPathComponent(".cargo")
    }

    private var cratesFile: URL {
        cargoHome.appendingPathComponent(".crates2.json")
    }

    private func makePackage(key: String, install: CargoInstall) -> Package? {
        guard let parsed = parseInstallKey(key) else { return nil }
        let binPath = install.bins?.first.map {
            cargoHome.appendingPathComponent("bin").appendingPathComponent($0)
        }

        return Package(
            id: "cargo::\(parsed.name)",
            manager: .cargo,
            qualifier: nil,
            name: parsed.name,
            version: parsed.version,
            installPath: binPath ?? cargoHome,
            installedAt: binPath.flatMap { directoryAccess.modificationDate(at: $0) }
                ?? directoryAccess.modificationDate(at: cratesFile),
            installedAtConfidence: .medium,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date()
        )
    }

    /// Cargo install keys look like:
    /// `ripgrep 14.1.0 (registry+https://github.com/rust-lang/crates.io-index)`.
    private func parseInstallKey(_ key: String) -> (name: String, version: String)? {
        let packageAndVersion: String
        if let sourceRange = key.range(of: " (") {
            packageAndVersion = String(key[..<sourceRange.lowerBound])
        } else {
            packageAndVersion = key
        }

        let parts = packageAndVersion.split(separator: " ")
        guard parts.count >= 2, let version = parts.last else { return nil }
        let name = parts.dropLast().joined(separator: " ")
        guard !name.isEmpty else { return nil }
        return (name, String(version))
    }
}

private struct CargoCratesMetadata: Decodable, Sendable {
    let installs: [String: CargoInstall]
}

private struct CargoInstall: Decodable, Sendable {
    let bins: [String]?
}
