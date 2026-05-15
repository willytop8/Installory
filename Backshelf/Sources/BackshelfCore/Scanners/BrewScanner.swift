import Foundation

/// Scans Homebrew formulae and casks by reading `INSTALL_RECEIPT.json` files
/// directly from the Cellar and Caskroom directories under each Homebrew prefix.
///
/// No `brew` invocation is made. The receipt files are the authoritative source
/// of truth for install time, explicit/dependency status, and runtime dependencies.
public struct BrewScanner: PackageScanner, Sendable {
    public let manager: PackageManager = .brew

    private let pathDiscovery: PathDiscovery
    private let directoryAccess: any DirectoryAccessProvider

    public init(
        pathDiscovery: PathDiscovery = PathDiscovery(),
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider()
    ) {
        self.pathDiscovery = pathDiscovery
        self.directoryAccess = directoryAccess
    }

    // MARK: - PackageScanner

    public func isAvailable() async -> Bool {
        !pathDiscovery.homebrewPrefixes.isEmpty
    }

    public func scan() async throws -> [Package] {
        var packages: [Package] = []
        for prefix in pathDiscovery.homebrewPrefixes {
            packages += try packagesIn(subdirectory: "Cellar", of: prefix, manager: .brew)
            packages += try packagesIn(subdirectory: "Caskroom", of: prefix, manager: .brewCask)
        }
        return packages
    }

    // MARK: - Private

    private func packagesIn(
        subdirectory: String,
        of prefix: URL,
        manager: PackageManager
    ) throws -> [Package] {
        let root = prefix.appendingPathComponent(subdirectory)
        let nameDirs: [URL]
        do {
            nameDirs = try directoryAccess.contentsOfDirectory(at: root)
        } catch {
            // Cellar or Caskroom doesn't exist under this prefix — not an error.
            return []
        }

        var packages: [Package] = []
        for nameDir in nameDirs {
            let pkgName = nameDir.lastPathComponent
            guard !pkgName.hasPrefix(".") else { continue }

            let versionDirs: [URL]
            do {
                versionDirs = try directoryAccess.contentsOfDirectory(at: nameDir)
            } catch {
                continue
            }

            for versionDir in versionDirs {
                let version = versionDir.lastPathComponent
                guard !version.hasPrefix(".") else { continue }

                let receiptURL = versionDir.appendingPathComponent("INSTALL_RECEIPT.json")
                guard let receiptData = try? directoryAccess.data(contentsOf: receiptURL) else {
                    continue
                }
                guard let receipt = try? receiptDecoder.decode(InstallReceipt.self, from: receiptData) else {
                    continue
                }

                packages.append(makePackage(
                    name: pkgName,
                    version: version,
                    installPath: versionDir,
                    receipt: receipt,
                    manager: manager
                ))
            }
        }
        return packages
    }

    private func makePackage(
        name: String,
        version: String,
        installPath: URL,
        receipt: InstallReceipt,
        manager: PackageManager
    ) -> Package {
        let id = "\(manager.rawValue)::\(name)"
        let installedAt = receipt.time.map { Date(timeIntervalSince1970: $0) }
        let deps = receipt.runtimeDependencies?.map(\.name) ?? []
        let isExplicit = receipt.installedOnRequest ?? !(receipt.installedAsDependency ?? false)
        let artifactPaths = manager == .brewCask ? receipt.artifactPaths : nil

        return Package(
            id: id,
            manager: manager,
            qualifier: nil,
            name: name,
            version: version,
            installPath: installPath,
            installedAt: installedAt,
            installedAtConfidence: .high,
            sizeBytes: nil,
            isExplicit: isExplicit,
            isReadOnly: false,
            dependencies: deps,
            artifactPaths: artifactPaths,
            lastSeen: Date()
        )
    }
}

// MARK: - Receipt format

private let receiptDecoder = JSONDecoder()

private struct InstallReceipt: Decodable {
    let time: Double?
    let installedOnRequest: Bool?
    let installedAsDependency: Bool?
    let runtimeDependencies: [RuntimeDep]?
    let artifacts: [Artifact]?

    var artifactPaths: [String]? {
        let paths = artifacts?.flatMap(\.paths) ?? []
        return paths.isEmpty ? nil : paths
    }

    struct RuntimeDep: Decodable {
        let fullName: String

        var name: String {
            fullName.components(separatedBy: "/").last ?? fullName
        }

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    struct Artifact: Decodable {
        let app: [String]?
        let zap: [Zap]?

        var paths: [String] {
            (app ?? []) + (zap ?? []).flatMap(\.trash)
        }
    }

    struct Zap: Decodable {
        let trash: [String]
    }

    enum CodingKeys: String, CodingKey {
        case time
        case installedOnRequest = "installed_on_request"
        case installedAsDependency = "installed_as_dependency"
        case runtimeDependencies = "runtime_dependencies"
        case artifacts
    }
}
