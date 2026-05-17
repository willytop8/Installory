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

    // MARK: - Snapshot state

    private(set) var snapshots: [Snapshot] = []
    private var snapshotManager: SnapshotManager?

    // MARK: - Cleanup state

    var selectedForCleanup: Set<String> = []
    var isCleanupMode: Bool = false
    var cleanupSheetScript: GeneratedScript? = nil

    // MARK: - Onboarding

    var onboardingCompleted: Bool = UserDefaults.standard.bool(forKey: "backshelf.onboarding.completed")

    // MARK: - Description corpus

    private(set) var descriptionStore: DescriptionStore = DescriptionStore()

    // MARK: - Infrastructure

    let folderAccess = FolderAccessManager()
    private(set) var database: Database?
    private var packageDAO: PackageDAO?
    private var scanRunDAO: ScanRunDAO?

    // MARK: - Init

    init() {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let dir = appSupport.appendingPathComponent("Backshelf", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let db = try? Database(directory: dir) {
                database = db
                packageDAO = PackageDAO(database: db)
                scanRunDAO = ScanRunDAO(database: db)
                snapshotManager = SnapshotManager(database: db)
                // Load the last persisted scan synchronously so the UI populates before the
                // first background re-scan completes. Errors are swallowed — the fallback
                // is an empty list, which auto-scan corrects shortly after launch.
                packages = (try? packageDAO!.loadAll()) ?? []
                lastScanCompletedAt = try? scanRunDAO!.mostRecentCompletedAt()
            }
        }

        folderAccess.loadPersistedBookmarks()
        restoreUIPreferences()
        loadDescriptionStore()
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

    var lastScanSummary: String? {
        guard let date = lastScanCompletedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last scanned \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    // MARK: - Actions

    func autoScanIfNeeded() async {
        guard folderAccess.hasAnyGrant else { return }
        await refreshSnapshots()
        await scan()
    }

    func refresh() async {
        await scan()
        await refreshSnapshots()
    }

    func grantDirectory(suggestedPath: String) async {
        await folderAccess.requestAccess(to: URL(fileURLWithPath: suggestedPath))
    }

    func grantCustomDirectory() async {
        await folderAccess.requestAccess(to: nil)
    }

    func persistUIPreferences() {
        UserDefaults.standard.set(sortOrder.rawValue, forKey: "backshelf.ui.sortOrder")
        if let sel = sidebarSelection, case .snapshot = sel {
            return  // do not persist snapshot selection — the ID may not exist on next launch
        }
        if let sel = sidebarSelection {
            UserDefaults.standard.set(sel.userDefaultsKey, forKey: "backshelf.ui.sidebarSelection")
        }
    }

    func completeOnboarding() {
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: "backshelf.onboarding.completed")
    }

    func refreshSnapshots() async {
        guard let sm = snapshotManager else { return }
        snapshots = (try? await sm.list()) ?? []
    }

    func captureManualSnapshot() async {
        guard let sm = snapshotManager else { return }
        _ = try? await sm.capture(packages: packages, reason: .manual, note: nil)
        await refreshSnapshots()
    }

    func generateAndShowCleanupScript(packages packagesToRemove: [Package]) async {
        guard !packagesToRemove.isEmpty else { return }

        var snapshotCtx: SnapshotContext? = nil
        if let sm = snapshotManager {
            if let snap = try? await sm.capture(packages: packages, reason: .preCleanup, note: nil) {
                snapshotCtx = SnapshotContext(id: snap.id, createdAt: snap.createdAt)
                await refreshSnapshots()
            }
        }

        let generator = ScriptGenerator()
        cleanupSheetScript = generator.generate(packages: packagesToRemove, snapshot: snapshotCtx)
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

    private func loadDescriptionStore() {
        guard let url = Bundle.main.url(forResource: "descriptions", withExtension: "json"),
              let store = try? DescriptionStore(contentsOf: url) else { return }
        descriptionStore = store
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
        let scanStartedAt = Date()
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

        // Persist the fresh package list and record this scan run.
        if let dao = packageDAO {
            try? dao.replaceAll(with: packages)
        }
        if let dao = scanRunDAO {
            let scanRun = ScanRun(
                id: UUID(),
                startedAt: scanStartedAt,
                completedAt: lastScanCompletedAt,
                perManagerResults: scanStatuses
            )
            try? dao.save(scanRun)
        }
    }
}
