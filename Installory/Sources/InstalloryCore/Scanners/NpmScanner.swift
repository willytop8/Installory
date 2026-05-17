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
        var seenIDs: Set<String> = []
        return deduplicatedNodeModulesDirs()
            .flatMap { packagesIn(nodeModulesDir: $0) }
            .filter { seenIDs.insert($0.id).inserted }
    }

    // MARK: - Private

    /// Returns candidate global node_modules directories from all known Node
    /// installation roots, with nvm and Volta version directories sorted for
    /// deterministic ordering across runs.
    private func nodeModulesDirs() -> [URL] {
        var dirs: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/lib/node_modules"),
            URL(fileURLWithPath: "/usr/local/lib/node_modules"),
        ]

        // nvm: ~/.nvm/versions/node/*/lib/node_modules — sorted for stable qualifier assignment
        let nvmRoot = homeDirectory.appendingPathComponent(".nvm/versions/node")
        for version in childDirectories(of: nvmRoot).sorted(by: { $0.path < $1.path }) {
            dirs.append(version.appendingPathComponent("lib/node_modules"))
        }

        // Volta: ~/.volta/tools/image/node/*/lib/node_modules — sorted for stable qualifier assignment
        let voltaRoot = homeDirectory.appendingPathComponent(".volta/tools/image/node")
        for version in childDirectories(of: voltaRoot).sorted(by: { $0.path < $1.path }) {
            dirs.append(version.appendingPathComponent("lib/node_modules"))
        }

        return dirs
    }

    /// Returns `nodeModulesDirs()` with duplicates removed by resolved symlink path.
    /// The first candidate whose resolved path is unseen is kept; its pre-resolution
    /// URL is preserved so Package IDs remain stable across runs.
    private func deduplicatedNodeModulesDirs() -> [URL] {
        var seenResolved: Set<String> = []
        var result: [URL] = []
        for dir in nodeModulesDirs() {
            let resolved = directoryAccess.resolvingSymlinks(at: dir).path
            guard seenResolved.insert(resolved).inserted else { continue }
            result.append(dir)
        }
        return result
    }

    private func packagesIn(nodeModulesDir: URL) -> [Package] {
        guard let entries = try? directoryAccess.contentsOfDirectory(at: nodeModulesDir) else {
            return []
        }
        var packages: [Package] = []
        var seenResolvedPaths: Set<String> = []

        for entry in entries {
            let entryName = entry.lastPathComponent
            guard !entryName.hasPrefix(".") else { continue }

            if entryName.hasPrefix("@") {
                // Scoped directory — each immediate child is a package
                let children = (try? directoryAccess.contentsOfDirectory(at: entry)) ?? []
                for child in children {
                    let childName = child.lastPathComponent
                    guard !childName.hasPrefix(".") else { continue }
                    let resolved = directoryAccess.resolvingSymlinks(at: child).path
                    guard seenResolvedPaths.insert(resolved).inserted else { continue }
                    let fullName = "\(entryName)/\(childName)"
                    if let pkg = makePackage(packageDir: child, packageName: fullName, nodeModulesDir: nodeModulesDir) {
                        packages.append(pkg)
                    }
                }
            } else {
                let resolved = directoryAccess.resolvingSymlinks(at: entry).path
                guard seenResolvedPaths.insert(resolved).inserted else { continue }
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
