import InstalloryCore
import Foundation

/// The result of a cleanup-script generation, carrying both the script and
/// the snapshot outcome. The sheet uses these flags to decide what status to show:
///  - `snapshotTaken == true`: snapshot was captured successfully.
///  - `snapshotFailed == true`: snapshot was requested but could not be saved.
///  - Both false: user chose to skip the snapshot (Never preference or explicit skip).
struct CleanupResult: Identifiable {
    let id = UUID()
    let script: GeneratedScript
    let snapshotTaken: Bool
    let snapshotFailed: Bool
}

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
    var cleanupResult: CleanupResult? = nil

    // MARK: - Onboarding

    // UserDefaults keys retain the "backshelf." prefix from a prior product name.
    // Kept deliberately — renaming them would orphan existing users' settings. Not worth a migration.
    var onboardingCompleted: Bool = UserDefaults.standard.bool(forKey: "backshelf.onboarding.completed")

    // MARK: - Settings

    var snapshotBeforeRemoval: SnapshotPreference = .ask
    var scanOnLaunch: Bool = true
    var provenanceCollection: Bool = true

    // MARK: - Removal flow (coordinator-driven "Ask" dialog)

    /// Non-nil when the user triggered a per-package removal and the snapshot
    /// preference is `.ask`. RootView presents the snapshot-choice sheet while
    /// this is set; the sheet clears it on confirm or cancel.
    var pendingRemovalPackages: [Package]? = nil

    // MARK: - Provenance

    /// In-memory provenance evidence keyed by package id, populated after each scan.
    /// Updated atomically at the end of provenance collection; never partially filled.
    /// Stale entries for removed packages are harmless — they're never selected.
    private(set) var provenanceByPackageId: [String: ProvenanceEvidence] = [:]
    private var provenanceDAO: ProvenanceDAO?

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
            let dir = appSupport.appendingPathComponent("Installory", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let db = try? Database(directory: dir) {
                database = db
                packageDAO = PackageDAO(database: db)
                scanRunDAO = ScanRunDAO(database: db)
                snapshotManager = SnapshotManager(database: db)
                provenanceDAO = ProvenanceDAO(database: db)
                packages = (try? packageDAO!.loadAll()) ?? []
                lastScanCompletedAt = try? scanRunDAO!.mostRecentCompletedAt()
            }
        }

        folderAccess.loadPersistedBookmarks()
        restoreUIPreferences()
        restoreSettings()
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
        guard folderAccess.hasAnyGrant, scanOnLaunch else { return }
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

    func persistSettings() {
        UserDefaults.standard.set(
            snapshotBeforeRemoval.rawValue,
            forKey: "backshelf.settings.snapshotBeforeRemoval"
        )
        UserDefaults.standard.set(scanOnLaunch, forKey: "backshelf.settings.scanOnLaunch")
        UserDefaults.standard.set(provenanceCollection, forKey: "backshelf.settings.provenanceCollection")
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

    // MARK: - Removal flow

    /// Entry point for all per-package removal. Checks the snapshot preference
    /// and either proceeds immediately or raises pending-removal state so RootView
    /// can present the snapshot-choice sheet. Both the detail pane and the row
    /// context menu call this method — one code path regardless of entry point.
    func requestRemoval(_ packages: [Package]) async {
        guard !packages.isEmpty else { return }
        switch snapshotBeforeRemoval {
        case .always:
            await generateAndShowCleanupScript(packages: packages, captureSnapshot: true)
        case .never:
            await generateAndShowCleanupScript(packages: packages, captureSnapshot: false)
        case .ask:
            pendingRemovalPackages = packages
        }
    }

    /// Called by SnapshotChoiceSheet when the user answers the snapshot question.
    /// Clears the pending state (dismisses the sheet), optionally persists the choice,
    /// then proceeds to script generation.
    func confirmRemoval(packages: [Package], takeSnapshot: Bool, remember: Bool) async {
        if remember {
            snapshotBeforeRemoval = takeSnapshot ? .always : .never
            persistSettings()
        }
        pendingRemovalPackages = nil
        await generateAndShowCleanupScript(packages: packages, captureSnapshot: takeSnapshot)
    }

    /// Called when the user dismisses the snapshot-choice sheet without choosing.
    func cancelRemoval() {
        pendingRemovalPackages = nil
    }

    /// Generates a cleanup script, optionally capturing a snapshot first.
    ///
    /// - Parameters:
    ///   - packagesToRemove: The packages to remove.
    ///   - captureSnapshot: When `true`, a `.preCleanup` snapshot is captured before
    ///     generating the script. Batch cleanup always passes `true`. Per-package
    ///     removal routes through `requestRemoval(_:)` which resolves the preference.
    ///
    /// The snapshot records exactly the packages this operation will remove — it is
    /// the restore point for *this cleanup*, so its scope matches the generated
    /// script. The restore flow diffs it against live inventory to find what to
    /// reinstall.
    ///
    /// The resulting `CleanupResult` records whether a snapshot was *actually*
    /// captured — not merely requested. If `captureSnapshot` is true but the
    /// capture fails, `snapshotTaken` is false, so the sheet never claims a
    /// snapshot exists when it does not.
    func generateAndShowCleanupScript(packages packagesToRemove: [Package], captureSnapshot: Bool) async {
        guard !packagesToRemove.isEmpty else { return }

        var snapshotCtx: SnapshotContext? = nil
        var snapshotFailed = false
        if captureSnapshot, let sm = snapshotManager {
            // The snapshot captures the packages being removed — it is the
            // restore point for this specific cleanup, so its scope matches
            // the generated script.
            if let snap = try? await sm.capture(
                packages: packagesToRemove,
                reason: .preCleanup,
                note: nil
            ) {
                snapshotCtx = SnapshotContext(id: snap.id, createdAt: snap.createdAt)
                await refreshSnapshots()
            } else {
                // Snapshot was requested but the capture failed. The sheet must
                // show a prominent warning — this is different from the user
                // having chosen to skip the snapshot.
                snapshotFailed = true
            }
        }

        let generator = ScriptGenerator()
        let script = generator.generate(packages: packagesToRemove, snapshot: snapshotCtx)
        cleanupResult = CleanupResult(
            script: script,
            snapshotTaken: snapshotCtx != nil,
            snapshotFailed: snapshotFailed
        )
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

    private func restoreSettings() {
        if let raw = UserDefaults.standard.string(forKey: "backshelf.settings.snapshotBeforeRemoval"),
           let pref = SnapshotPreference(rawValue: raw) {
            snapshotBeforeRemoval = pref
        }
        // Bool defaults are `false` in UserDefaults when not yet set, but our
        // defaults for both flags are `true`. Guard with object(forKey:) to
        // distinguish "never written" (keep true) from "explicitly written false".
        if UserDefaults.standard.object(forKey: "backshelf.settings.scanOnLaunch") != nil {
            scanOnLaunch = UserDefaults.standard.bool(forKey: "backshelf.settings.scanOnLaunch")
        }
        if UserDefaults.standard.object(forKey: "backshelf.settings.provenanceCollection") != nil {
            provenanceCollection = UserDefaults.standard.bool(
                forKey: "backshelf.settings.provenanceCollection"
            )
        }
    }

    private func loadDescriptionStore() {
        guard let url = Bundle.main.url(forResource: "descriptions", withExtension: "json"),
              let store = try? DescriptionStore(contentsOf: url) else { return }
        descriptionStore = store
    }

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

        if let dao = packageDAO {
            try? dao.replaceAll(with: packages)
        }

        // Capture an autoFirstScan snapshot the very first time the scan
        // completes with results. Subsequent scans skip this entirely.
        // The "backshelf." prefix is retained from the prior product name
        // to keep the key stable across the rename.
        if !packages.isEmpty,
           !UserDefaults.standard.bool(forKey: "backshelf.firstScanSnapshotTaken"),
           let sm = snapshotManager {
            _ = try? await sm.capture(packages: packages, reason: .autoFirstScan, note: nil)
            UserDefaults.standard.set(true, forKey: "backshelf.firstScanSnapshotTaken")
            await refreshSnapshots()
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

        // Provenance collection runs off the main thread after packages are persisted.
        // packageDAO.replaceAll cascades ON DELETE CASCADE through provenance_evidence,
        // so collection always runs fresh and there are no stale rows to upsert over.
        // FK ordering is satisfied: packages row exists before provenance_evidence row.
        if provenanceCollection, let dao = provenanceDAO {
            let pkgs = packages
            let evidence = await Task.detached(priority: .utility) {
                ProvenanceCollector().collect(packages: pkgs)
            }.value
            for e in evidence {
                try? await dao.upsert(e)
            }
            // Atomic swap — the detail pane never sees a partial dict.
            provenanceByPackageId = Dictionary(
                uniqueKeysWithValues: evidence.map { ($0.packageId, $0) }
            )
        }
    }
}
