import Foundation

/// Scans globally installed npm packages by reading `package.json` files
/// from each known global `node_modules` directory.
///
/// No `npm` or `node` invocation is made. All data comes from reading
/// `package.json` files directly from known on-disk locations.
///
/// Each node_modules root is treated as a separate installation, so the
/// same package name across different Node installations (brew, nvm, Volta)
/// produces distinct `Package` rows tagged with the node_modules path as
/// `qualifier`.
public struct NpmScanner: PackageScanner, Sendable {
    public let manager: PackageManager = .npm

    private let directoryAccess: any DirectoryAccessProvider
    private let homeDirectory: URL

    public init(
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) {
        self.directoryAccess = directoryAccess
        self.homeDirectory = homeDirectory
    }

    // MARK: - PackageScanner

    public func isAvailable() async -> Bool {
        nodeModulesDirs().contains { directoryAccess.fileExists(at: $0) }
    }

    public func scan() async throws -> [Package] {
        nodeModulesDirs().flatMap { packagesIn(nodeModulesDir: $0) }
    }

    // MARK: - Private

    /// Returns candidate global node_modules directories from all known Node installation roots.
    /// Directories that don't exist are included in the list; callers skip them silently.
    private func nodeModulesDirs() -> [URL] {
        var dirs: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/lib/node_modules"),
            URL(fileURLWithPath: "/usr/local/lib/node_modules"),
        ]

        // nvm: ~/.nvm/versions/node/*/lib/node_modules
        let nvmRoot = homeDirectory.appendingPathComponent(".nvm/versions/node")
        for version in childDirectories(of: nvmRoot) {
            dirs.append(version.appendingPathComponent("lib/node_modules"))
        }

        // Volta: ~/.volta/tools/image/node/*/lib/node_modules
        let voltaRoot = homeDirectory.appendingPathComponent(".volta/tools/image/node")
        for version in childDirectories(of: voltaRoot) {
            dirs.append(version.appendingPathComponent("lib/node_modules"))
        }

        return dirs
    }

    private func packagesIn(nodeModulesDir: URL) -> [Package] {
        guard let entries = try? directoryAccess.contentsOfDirectory(at: nodeModulesDir) else {
            return []
        }
        var packages: [Package] = []
        for entry in entries {
            let entryName = entry.lastPathComponent
            guard !entryName.hasPrefix(".") else { continue }

            if entryName.hasPrefix("@") {
                // Scoped directory — each immediate child is a package
                let children = (try? directoryAccess.contentsOfDirectory(at: entry)) ?? []
                for child in children {
                    let childName = child.lastPathComponent
                    guard !childName.hasPrefix(".") else { continue }
                    let fullName = "\(entryName)/\(childName)"
                    if let pkg = makePackage(packageDir: child, packageName: fullName, nodeModulesDir: nodeModulesDir) {
                        packages.append(pkg)
                    }
                }
            } else {
                if let pkg = makePackage(packageDir: entry, packageName: entryName, nodeModulesDir: nodeModulesDir) {
                    packages.append(pkg)
                }
            }
        }
        return packages
    }

    private func makePackage(
        packageDir: URL,
        packageName: String,
        nodeModulesDir: URL
    ) -> Package? {
        let packageJsonURL = packageDir.appendingPathComponent("package.json")
        guard let data = try? directoryAccess.data(contentsOf: packageJsonURL),
              let json = try? npmJSONDecoder.decode(PackageJSON.self, from: data),
              let version = json.version
        else { return nil }

        // JSON object key order is non-deterministic; sort for snapshot stability.
        let deps = json.dependencies.map { $0.keys.sorted() } ?? []

        return Package(
            id: "npm:\(nodeModulesDir.path):\(packageName)",
            manager: .npm,
            qualifier: nodeModulesDir.path,
            name: json.name ?? packageName,
            version: version,
            installPath: packageDir,
            installedAt: directoryAccess.modificationDate(at: packageJsonURL),
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: deps,
            lastSeen: Date()
        )
    }

    private func childDirectories(of url: URL) -> [URL] {
        (try? directoryAccess.contentsOfDirectory(at: url)) ?? []
    }
}

// MARK: - package.json format

private let npmJSONDecoder = JSONDecoder()

private struct PackageJSON: Decodable, Sendable {
    let name: String?
    let version: String?
    let dependencies: [String: String]?
}
