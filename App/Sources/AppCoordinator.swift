import BackshelfCore
import Foundation

@Observable
@MainActor
final class AppCoordinator {
    // MARK: - Scan state

    private(set) var packages: [Package] = []
    private(set) var scanStatuses: [PackageManager: ScannerStatus] = [:]
    private(set) var isScanning = false
    private(set) var lastScanCompletedAt: Date?

    // MARK: - UI state

    var searchQuery: String = ""
    var sidebarSelection: SidebarSelection? = .all
    var sortOrder: PackageSortOrder = .recentlyInstalled
    var selectedPackage: Package?

    // MARK: - Infrastructure

    let folderAccess = FolderAccessManager()
    private(set) var database: Database?

    // MARK: - Init

    init() {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let dir = appSupport.appendingPathComponent("Backshelf", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            database = try? Database(directory: dir)
        }

        folderAccess.loadPersistedBookmarks()
        restoreUIPreferences()
    }

    // MARK: - Computed: packages

    var filteredPackages: [Package] {
        packages.filtered(by: sidebarSelection, query: searchQuery).sorted(by: sortOrder)
    }

    // MARK: - Computed: directories

    var grantedDirectories: [GrantedDirectory] {
        folderAccess.grantedBookmarks().map {
            GrantedDirectory(path: $0.path, bookmark: $0.bookmark)
        }
    }

    var ungrantedCanonicalDirectories: [CanonicalDirectory] {
        let grantedPaths = folderAccess.grantedPaths
        return CanonicalDirectory.all(isAppleSilicon: isAppleSilicon)
            .filter { dir in
                !grantedPaths.contains { granted in
                    granted.hasPrefix(dir.path) || dir.path.hasPrefix(granted)
                }
            }
    }

    // MARK: - Computed: status

    var statusSummary: String {
        let dirs = grantedDirectories.count
        let managers = Set(packages.map(\.manager)).count
        let pkgs = packages.count
        return "\(dirs) \(dirs == 1 ? "directory" : "directories"), "
            + "\(managers) \(managers == 1 ? "manager" : "managers"), "
            + "\(pkgs) \(pkgs == 1 ? "package" : "packages")"
    }

    // MARK: - Actions

    func autoScanIfNeeded() async {
        guard folderAccess.hasAnyGrant else { return }
        await scan()
    }

    func refresh() async {
        await scan()
    }

    func grantDirectory(suggestedPath: String) async {
        await folderAccess.requestAccess(to: URL(fileURLWithPath: suggestedPath))
    }

    func grantCustomDirectory() async {
        await folderAccess.requestAccess(to: nil)
    }

    func persistUIPreferences() {
        UserDefaults.standard.set(sortOrder.rawValue, forKey: "backshelf.ui.sortOrder")
        if let sel = sidebarSelection {
            UserDefaults.standard.set(sel.userDefaultsKey, forKey: "backshelf.ui.sidebarSelection")
        }
    }

    // MARK: - Private

    private func restoreUIPreferences() {
        if let raw = UserDefaults.standard.string(forKey: "backshelf.ui.sortOrder"),
           let sort = PackageSortOrder(rawValue: raw) {
            sortOrder = sort
        }
        if let raw = UserDefaults.standard.string(forKey: "backshelf.ui.sidebarSelection"),
           let sel = SidebarSelection(userDefaultsKey: raw) {
            sidebarSelection = sel
        }
    }

    // Compile-time arch check. Correct for native binaries; Rosetta processes return false.
    private var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Scan

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        // Start security-scoped access for all granted bookmarks before any scanner runs.
        // All scanners use SystemDirectoryAccessProvider (FileManager) which cannot see
        // directories outside the sandbox container without this.
        var accessedURLs: [URL] = []
        for (_, data) in folderAccess.grantedBookmarks() {
            if let url = folderAccess.startAccessing(data) {
                accessedURLs.append(url)
            }
        }
        defer {
            for url in accessedURLs { folderAccess.stopAccessing(url) }
        }

        let scanners: [any PackageScanner] = [
            BrewScanner(),
            PipScanner(),
            NpmScanner(),
        ]
        let scanCoordinator = ScanCoordinator(scanners: scanners)

        packages = []
        scanStatuses = [:]

        for await event in await scanCoordinator.scan() {
            switch event {
            case .scannerStarted:
                break
            case let .scannerFinished(manager, status, pkgs):
                scanStatuses[manager] = status
                packages += pkgs
            case let .allFinished(perManager, allPackages):
                scanStatuses = perManager
                packages = allPackages
            }
        }

        lastScanCompletedAt = Date()
    }
}
