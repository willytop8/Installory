import Foundation

/// Scans Mac App Store applications by reading app bundles that contain an
/// App Store receipt at `Contents/_MASReceipt/receipt`.
///
/// This intentionally does not invoke the `mas` CLI. In the sandbox, users must
/// grant read access to `/Applications` or `~/Applications` for this scanner to
/// see app bundles.
public struct MasScanner: PackageScanner, Sendable {
    public let manager: PackageManager = .mas

    private let directoryAccess: any DirectoryAccessProvider
    private let homeDirectory: URL
    private let explicitApplicationDirectories: [URL]?

    public init(
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationDirectories: [URL]? = nil
    ) {
        self.directoryAccess = directoryAccess
        self.homeDirectory = homeDirectory
        self.explicitApplicationDirectories = applicationDirectories
    }

    public func isAvailable() async -> Bool {
        applicationDirectories().contains { (try? directoryAccess.contentsOfDirectory(at: $0)) != nil }
    }

    public var unavailableReason: String {
        "Applications folder not granted or not found"
    }

    public func scan() async throws -> [Package] {
        var seen: Set<String> = []
        return applicationDirectories()
            .flatMap(packagesInApplicationsDir)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name < $1.name }
    }

    private func applicationDirectories() -> [URL] {
        if let explicitApplicationDirectories {
            return explicitApplicationDirectories
        }
        return [
            URL(fileURLWithPath: "/Applications"),
            homeDirectory.appendingPathComponent("Applications"),
        ]
    }

    private func packagesInApplicationsDir(_ applicationsDir: URL) -> [Package] {
        let apps = (try? directoryAccess.contentsOfDirectory(at: applicationsDir)) ?? []
        return apps
            .filter { $0.pathExtension == "app" }
            .compactMap(makePackage(appBundle:))
    }

    private func makePackage(appBundle: URL) -> Package? {
        let receipt = appBundle
            .appendingPathComponent("Contents")
            .appendingPathComponent("_MASReceipt")
            .appendingPathComponent("receipt")
        guard directoryAccess.fileExists(at: receipt) else { return nil }

        let infoPlist = appBundle
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        let info = parseInfoPlist(at: infoPlist)

        let fallbackName = appBundle.deletingPathExtension().lastPathComponent
        let name = info.displayName ?? info.name ?? fallbackName
        let identity = info.bundleIdentifier ?? name
        let version = info.shortVersion ?? info.bundleVersion ?? "unknown"

        return Package(
            id: "mas::\(identity)",
            manager: .mas,
            qualifier: nil,
            name: name,
            version: version,
            installPath: appBundle,
            installedAt: directoryAccess.modificationDate(at: receipt)
                ?? directoryAccess.modificationDate(at: appBundle),
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            artifactPaths: [appBundle.path],
            lastSeen: Date()
        )
    }

    private func parseInfoPlist(at url: URL) -> AppBundleInfo {
        guard let data = try? directoryAccess.data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return AppBundleInfo()
        }

        return AppBundleInfo(
            bundleIdentifier: dict["CFBundleIdentifier"] as? String,
            displayName: dict["CFBundleDisplayName"] as? String,
            name: dict["CFBundleName"] as? String,
            shortVersion: dict["CFBundleShortVersionString"] as? String,
            bundleVersion: dict["CFBundleVersion"] as? String
        )
    }
}

private struct AppBundleInfo: Sendable {
    var bundleIdentifier: String?
    var displayName: String?
    var name: String?
    var shortVersion: String?
    var bundleVersion: String?
}
