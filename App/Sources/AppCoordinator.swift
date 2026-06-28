import AppKit
import InstalloryCore
import Foundation
import UniformTypeIdentifiers

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

/// Canonical UserDefaults key names. The original product was named "Backshelf";
/// keys carry an `app.installory.` prefix today and a one-time migration in
/// `init` copies any pre-existing `backshelf.` keys forward so settings survive
/// the rename without orphaning anyone.
private enum DefaultsKey {
    static let onboardingCompleted   = "app.installory.onboarding.completed"
    static let sortOrder             = "app.installory.ui.sortOrder"
    static let sidebarSelection      = "app.installory.ui.sidebarSelection"
    static let snapshotBeforeRemoval = "app.installory.settings.snapshotBeforeRemoval"
    static let scanOnLaunch          = "app.installory.settings.scanOnLaunch"
    static let firstScanTaken        = "app.installory.firstScanSnapshotTaken"
    static let migrationCompleted    = "app.installory.migration.fromBackshelf"
    static let provenanceCollection  = "app.installory.settings.provenanceCollection"
}

@Observable
@MainActor
final class AppCoordinator {
    // MARK: - Scan state

    private(set) var packages: [Package] = []
    private(set) var scanStatuses: [PackageManager: ScannerStatus] = [:]
    private(set) var isScanning = false
    private(set) var lastScanCompletedAt: Date?

    /// Non-nil when local persistence is unavailable — the SQLite cache couldn't
    /// be opened, or a save failed. The UI surfaces this so results that silently
    /// won't be remembered between launches don't look like a mysterious bug.
    private(set) var storageWarning: String?

    /// Managers whose scan is currently in flight, used for per-manager progress
    /// in the scanning empty state.
    private(set) var inFlightManagers: Set<PackageManager> = []

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

    var onboardingCompleted: Bool = UserDefaults.standard.bool(forKey: DefaultsKey.onboardingCompleted)

    // MARK: - Demo mode

    /// When true, the app is showing pre-populated sample data instead of a real
    /// scan. Demo mode is fully self-contained: it never reads the filesystem,
    /// writes to the database, or makes network calls. It exists so the app's
    /// full feature set can be verified on a machine with no package managers
    /// installed (for example, App Review's clean test device).
    private(set) var isDemoMode: Bool = false

    /// True when the process was launched in demo mode via `-demo` argument or
    /// the `INSTALLORY_DEMO=1` environment variable. Lets App Review script the
    /// demo without any clicks.
    private static var demoLaunchRequested: Bool {
        CommandLine.arguments.contains("-demo")
            || ProcessInfo.processInfo.environment["INSTALLORY_DEMO"] == "1"
    }

    // MARK: - Settings

    var snapshotBeforeRemoval: SnapshotPreference = .ask
    var scanOnLaunch: Bool = true

    /// When true, Installory reads shell history and Claude Code session logs
    /// during scans to build install-origin evidence per package.
    ///
    /// Defaults to `false`. The collectors must never be called until the user
    /// explicitly opts in via Settings → Privacy → Provenance.
    var provenanceCollection: Bool = false

    // MARK: - Removal flow (coordinator-driven "Ask" dialog)

    /// Non-nil when the user triggered a per-package removal and the snapshot
    /// preference is `.ask`. RootView presents the snapshot-choice sheet while
    /// this is set; the sheet clears it on confirm or cancel.
    var pendingRemovalPackages: [Package]? = nil

    // MARK: - Description corpus

    private(set) var descriptionStore: DescriptionStore = DescriptionStore()

    // MARK: - Infrastructure

    let folderAccess = FolderAccessManager()
    private(set) var database: Database?
    private var packageDAO: PackageDAO?
    private var scanRunDAO: ScanRunDAO?
    private var provenanceDAO: ProvenanceDAO?
    private var dataDirectory: URL?

    /// Provenance evidence keyed by package ID. Populated at the end of each
    /// scan when `provenanceCollection` is true. Empty in demo mode until the
    /// orchestrator wires `DemoData.demoProvenanceByPackageId()`.
    private(set) var provenanceByPackageId: [String: ProvenanceEvidence] = [:]

    /// Minimum interval between automatic scans triggered by `autoScanIfNeeded`.
    /// Manual `refresh()` ignores this — the user pressing ⌘R always rescans.
    private static let autoScanCooldown: TimeInterval = 60

    // MARK: - Computed: provenance access

    /// True when a security-scoped bookmark covering the user's home directory
    /// exists in `FolderAccessManager`, indicating the user has granted read
    /// access for provenance collection.
    var provenanceAccessGranted: Bool {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return folderAccess.grantedPath(forPrefix: homePath) != nil
    }

    // MARK: - Init

    init() {
        migrateLegacyDefaultsIfNeeded()

        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let dir = appSupport.appendingPathComponent("Installory", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dataDirectory = dir
            if let db = try? Database(directory: dir) {
                database = db
                packageDAO = PackageDAO(database: db)
                scanRunDAO = ScanRunDAO(database: db)
                snapshotManager = SnapshotManager(database: db)
                provenanceDAO = ProvenanceDAO(database: db)
                packages = (try? packageDAO!.loadAll()) ?? []
                lastScanCompletedAt = try? scanRunDAO!.mostRecentCompletedAt()
            } else {
                storageWarning = "Couldn't open the local cache, so scan results won't be saved between launches."
            }
        } else {
            storageWarning = "Couldn't locate Application Support, so scan results won't be saved between launches."
        }

        folderAccess.loadPersistedBookmarks()
        restoreUIPreferences()
        restoreSettings()
        loadDescriptionStoreInBackground()

        // Allow App Review (or anyone) to launch straight into demo mode without
        // any clicks, via `-demo` or INSTALLORY_DEMO=1.
        if Self.demoLaunchRequested {
            enterDemoMode()
        }
    }

    // MARK: - Defaults migration

    /// Copies legacy `backshelf.*` keys to their `app.installory.*` equivalents
    /// the first time the renamed app launches. Old keys are left in place so a
    /// downgrade still finds its settings.
    private func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.migrationCompleted) else { return }

        let pairs: [(legacy: String, current: String, kind: DefaultsKind)] = [
            ("backshelf.onboarding.completed",            DefaultsKey.onboardingCompleted,   .bool),
            ("backshelf.ui.sortOrder",                    DefaultsKey.sortOrder,             .string),
            ("backshelf.ui.sidebarSelection",             DefaultsKey.sidebarSelection,      .string),
            ("backshelf.settings.snapshotBeforeRemoval",  DefaultsKey.snapshotBeforeRemoval, .string),
            ("backshelf.settings.scanOnLaunch",           DefaultsKey.scanOnLaunch,          .bool),
            ("backshelf.firstScanSnapshotTaken",          DefaultsKey.firstScanTaken,        .bool),
            ("backshelf.settings.provenanceCollection",   DefaultsKey.provenanceCollection,  .bool),
        ]
        for pair in pairs {
            guard defaults.object(forKey: pair.legacy) != nil,
                  defaults.object(forKey: pair.current) == nil
            else { continue }
            switch pair.kind {
            case .bool:
                defaults.set(defaults.bool(forKey: pair.legacy), forKey: pair.current)
            case .string:
                if let value = defaults.string(forKey: pair.legacy) {
                    defaults.set(value, forKey: pair.current)
                }
            }
        }
        defaults.set(true, forKey: DefaultsKey.migrationCompleted)
    }
    private enum DefaultsKind { case bool, string }

    // MARK: - Demo mode actions

    /// Loads the bundled sample inventory and snapshots into memory and switches
    /// the app into demo mode. No filesystem, database, or network access occurs.
    func enterDemoMode() {
        isDemoMode = true
        isScanning = false
        searchQuery = ""
        sidebarSelection = .all
        selectedPackage = nil
        isCleanupMode = false
        selectedForCleanup = []
        packages = DemoData.packages()
        snapshots = DemoData.snapshots()
        scanStatuses = [:]
        lastScanCompletedAt = Date()
        provenanceByPackageId = DemoData.demoProvenanceByPackageId()
        // Dismiss onboarding for the demo session without persisting the flag —
        // a developer who runs `-demo` once shouldn't permanently skip onboarding.
        onboardingCompleted = true
    }

    /// Leaves demo mode and restores the real (possibly empty) local state.
    func exitDemoMode() {
        isDemoMode = false
        packages = (try? packageDAO?.loadAll()) ?? []
        lastScanCompletedAt = try? scanRunDAO?.mostRecentCompletedAt()
        snapshots = []
        scanStatuses = [:]
        selectedPackage = nil
        isCleanupMode = false
        selectedForCleanup = []
        searchQuery = ""
        sidebarSelection = .all
        provenanceByPackageId = [:]
        onboardingCompleted = UserDefaults.standard.bool(forKey: DefaultsKey.onboardingCompleted)
        Task {
            await refreshSnapshots()
            await autoScanIfNeeded()
        }
    }

    // MARK: - Computed: packages

    var filteredPackages: [Package] {
        packages.filtered(by: sidebarSelection, query: searchQuery).sorted(by: sortOrder)
    }

    var duplicateGroups: [DuplicateGroup] {
        packages.crossManagerDuplicates()
    }

    /// Explicitly-installed packages that have no in-inventory dependents within
    /// their own package manager. See ``DependencyAnalysis`` for caveats.
    var orphanedPackages: [Package] {
        packages.orphanedPackages()
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
        if isScanning {
            let names = inFlightManagers.map(\.displayName).sorted()
            return names.isEmpty ? "Scanning…" : "Scanning \(names.joined(separator: ", "))…"
        }
        let pkgs = packages.count
        let managers = Set(packages.map(\.manager)).count
        if pkgs == 0 {
            return "Ready — no packages scanned yet."
        }
        let pkgWord = pkgs == 1 ? "package" : "packages"
        let mgrWord = managers == 1 ? "manager" : "managers"
        return "\(pkgs) \(pkgWord) across \(managers) \(mgrWord)."
    }

    var lastScanSummary: String? {
        guard let date = lastScanCompletedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last scanned \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    /// Per-manager status entries (managers that ran or were skipped/failed),
    /// sorted by display name. Used by the "Scan coverage" view.
    var scanCoverage: [(manager: PackageManager, status: ScannerStatus)] {
        scanStatuses
            .map { ($0.key, $0.value) }
            .sorted { $0.0.displayName < $1.0.displayName }
    }

    /// Managers whose last scan failed or timed out. Used by the aggregated
    /// "Some scans failed" banner above the package list.
    var failedManagers: [(PackageManager, String)] {
        scanStatuses.compactMap { (manager, status) -> (PackageManager, String)? in
            switch status {
            case .failed(let reason, _): return (manager, reason)
            case .timedOut:              return (manager, "Scan timed out")
            default:                     return nil
            }
        }
        .sorted { $0.0.displayName < $1.0.displayName }
    }

    // MARK: - Actions

    func autoScanIfNeeded() async {
        guard !isDemoMode else { return }
        guard folderAccess.hasAnyGrant, scanOnLaunch else { return }
        if let last = lastScanCompletedAt, Date().timeIntervalSince(last) < Self.autoScanCooldown {
            return
        }
        await refreshSnapshots()
        await scan()
    }

    func refresh() async {
        // In demo mode a "scan" just re-seeds the sample inventory — there is
        // nothing on disk to read.
        guard !isDemoMode else {
            enterDemoMode()
            return
        }
        await scan()
        await refreshSnapshots()
    }

    /// Rescan just one manager, leaving the rest of the inventory in place.
    /// Useful after the user fixes a perms issue or grants a new directory.
    func rescan(manager: PackageManager) async {
        guard !isDemoMode, !isScanning else { return }
        isScanning = true
        inFlightManagers = [manager]
        defer {
            isScanning = false
            inFlightManagers = []
        }

        var accessedURLs: [URL] = []
        for (_, data) in folderAccess.grantedBookmarks() {
            if let url = folderAccess.startAccessing(data) {
                accessedURLs.append(url)
            }
        }
        defer { for url in accessedURLs { folderAccess.stopAccessing(url) } }

        guard let scanner = scanner(for: manager, grantedURLs: accessedURLs) else { return }
        let coordinator = ScanCoordinator(scanners: [scanner])
        for await event in await coordinator.scan() {
            if case let .scannerFinished(mgr, status, pkgs) = event {
                scanStatuses[mgr] = status
                packages.removeAll { $0.manager == mgr }
                packages += pkgs
            }
        }
        lastScanCompletedAt = Date()
        if let dao = packageDAO {
            try? dao.replaceAll(with: packages)
        }
    }

    func grantDirectory(suggestedPath: String) async {
        guard await folderAccess.requestAccess(to: URL(fileURLWithPath: suggestedPath)) != nil else { return }
        Task { await refresh() }
    }

    func grantCustomDirectory() async {
        guard await folderAccess.requestAccess(to: nil) != nil else { return }
        Task { await refresh() }
    }

    func persistUIPreferences() {
        UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sortOrder)
        if let sel = sidebarSelection, case .snapshot = sel {
            return  // do not persist snapshot selection — the ID may not exist on next launch
        }
        if let sel = sidebarSelection {
            UserDefaults.standard.set(sel.userDefaultsKey, forKey: DefaultsKey.sidebarSelection)
        }
    }

    func persistSettings() {
        UserDefaults.standard.set(
            snapshotBeforeRemoval.rawValue,
            forKey: DefaultsKey.snapshotBeforeRemoval
        )
        UserDefaults.standard.set(scanOnLaunch, forKey: DefaultsKey.scanOnLaunch)
        UserDefaults.standard.set(provenanceCollection, forKey: DefaultsKey.provenanceCollection)
    }

    func completeOnboarding() {
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.onboardingCompleted)
    }

    /// Re-show the onboarding sheet on next view appearance. Used by Settings.
    func resetOnboarding() {
        onboardingCompleted = false
        UserDefaults.standard.set(false, forKey: DefaultsKey.onboardingCompleted)
    }

    /// Reveals the local data directory (Application Support/Installory) in Finder
    /// so users can see exactly what Installory persists.
    func revealDataFolder() {
        guard let dir = dataDirectory else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    /// Writes the current inventory to a user-chosen path as CSV or Markdown.
    /// Returns the URL on success, nil on cancel or failure.
    @discardableResult
    func exportInventory(format: InventoryExporter.Format) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Inventory"
        panel.nameFieldStringValue = "installory-inventory.\(format.fileExtension)"
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let content = InventoryExporter().export(packages, format: format)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    func refreshSnapshots() async {
        // Demo snapshots live only in memory — never overwrite them from the DB.
        guard !isDemoMode else { return }
        guard let sm = snapshotManager else { return }
        snapshots = (try? await sm.list()) ?? []
    }

    func captureManualSnapshot() async {
        // In demo mode, capture a snapshot in memory so the flow is demonstrable
        // without writing to the database.
        if isDemoMode {
            snapshots.insert(DemoData.makeSnapshot(reason: .manual, from: packages), at: 0)
            return
        }
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
    func generateAndShowCleanupScript(packages packagesToRemove: [Package], captureSnapshot: Bool) async {
        guard !packagesToRemove.isEmpty else { return }

        var snapshotCtx: SnapshotContext? = nil
        var snapshotFailed = false
        if captureSnapshot, isDemoMode {
            let snap = DemoData.makeSnapshot(reason: .preCleanup, from: packagesToRemove)
            snapshots.insert(snap, at: 0)
            snapshotCtx = SnapshotContext(id: snap.id, createdAt: snap.createdAt)
        } else if captureSnapshot, let sm = snapshotManager {
            if let snap = try? await sm.capture(
                packages: packagesToRemove,
                reason: .preCleanup,
                note: nil
            ) {
                snapshotCtx = SnapshotContext(id: snap.id, createdAt: snap.createdAt)
                await refreshSnapshots()
            } else {
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

    // MARK: - Provenance actions

    /// Presents an `NSOpenPanel` pre-navigated to the user's home directory so
    /// the user can grant Installory read access to their shell history and Claude
    /// Code session logs. The resulting security-scoped bookmark is stored in
    /// `FolderAccessManager` and persisted to UserDefaults.
    ///
    /// The open panel title and surrounding Settings UI copy explicitly name what
    /// will be read: `~/.zsh_history`, `~/.bash_history`,
    /// `~/.local/share/fish/fish_history`, and `~/.claude/projects/`.
    func requestProvenanceAccess() async {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        _ = await folderAccess.requestAccess(to: homeDir)
    }

    /// Removes the home-directory security-scoped bookmark used by provenance
    /// collection. Clears it from UserDefaults and reloads `FolderAccessManager`'s
    /// in-memory bookmark cache so `provenanceAccessGranted` updates immediately.
    ///
    /// Safe to call outside of an active scan (the Revoke button is shown only
    /// when the toggle is ON and the toggle is disabled while scanning).
    func revokeProvenanceAccess() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard let storedPath = folderAccess.grantedPath(forPrefix: homePath) else { return }
        // "app.installory.bookmarks" is the UserDefaults key used by FolderAccessManager.
        var bookmarks = UserDefaults.standard.dictionary(
            forKey: "app.installory.bookmarks"
        ) as? [String: Data] ?? [:]
        bookmarks.removeValue(forKey: storedPath)
        UserDefaults.standard.set(bookmarks, forKey: "app.installory.bookmarks")
        // Reload FolderAccessManager's in-memory state to reflect the removal.
        folderAccess.loadPersistedBookmarks()
    }

    /// Deletes all rows from `provenance_evidence` and clears the in-memory cache.
    /// Called when the user turns off provenance collection and confirms they want
    /// to erase stored install history.
    func clearProvenanceEvidence() async {
        try? await provenanceDAO?.deleteAll()
        provenanceByPackageId = [:]
    }

    // MARK: - Private

    private func restoreUIPreferences() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.sortOrder),
           let sort = PackageSortOrder(rawValue: raw) {
            sortOrder = sort
        }
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.sidebarSelection),
           let sel = SidebarSelection(userDefaultsKey: raw) {
            sidebarSelection = sel
        }
    }

    private func restoreSettings() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.snapshotBeforeRemoval),
           let pref = SnapshotPreference(rawValue: raw) {
            snapshotBeforeRemoval = pref
        }
        // Bool defaults are `false` in UserDefaults when not yet set.
        // Guard with object(forKey:) for settings whose product default differs
        // from the raw UserDefaults default.
        if UserDefaults.standard.object(forKey: DefaultsKey.scanOnLaunch) != nil {
            scanOnLaunch = UserDefaults.standard.bool(forKey: DefaultsKey.scanOnLaunch)
        }
        if UserDefaults.standard.object(forKey: DefaultsKey.provenanceCollection) != nil {
            provenanceCollection = UserDefaults.standard.bool(forKey: DefaultsKey.provenanceCollection)
        }
    }

    private func loadDescriptionStoreInBackground() {
        guard let url = Bundle.main.url(forResource: "descriptions", withExtension: "json") else { return }
        Task { [weak self] in
            let store = await Task.detached(priority: .utility) {
                try? DescriptionStore(contentsOf: url)
            }.value
            guard let store else { return }
            self?.descriptionStore = store
        }
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
        guard !isDemoMode else { return }
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

        let pythonDiscovery = PythonInterpreterDiscovery(
            projectVenvRoots: accessedURLs
        )
        let scanners: [any PackageScanner] = [
            BrewScanner(),
            PipScanner(discovery: pythonDiscovery),
            PipxScanner(),
            NpmScanner(),
            CargoScanner(),
            GemScanner(),
            MasScanner(applicationDirectories: grantedApplicationsDirectories(accessedURLs)),
        ]
        let scanCoordinator = ScanCoordinator(scanners: scanners)

        // Double-buffer: build into local vars so the UI doesn't briefly flip
        // to "empty" between clearing and the first scanner finishing.
        var buildPackages: [Package] = []
        var buildStatuses: [PackageManager: ScannerStatus] = [:]
        inFlightManagers = []

        for await event in await scanCoordinator.scan() {
            switch event {
            case let .scannerStarted(manager):
                inFlightManagers.insert(manager)
            case let .scannerFinished(manager, status, pkgs):
                inFlightManagers.remove(manager)
                buildStatuses[manager] = status
                buildPackages += pkgs
            case let .allFinished(perManager, allPackages):
                inFlightManagers = []
                buildStatuses = perManager
                buildPackages = allPackages
            }
        }

        // Swap in the freshly built results once. This is the only point
        // where `packages` and `scanStatuses` change during a scan.
        packages = buildPackages
        scanStatuses = buildStatuses
        inFlightManagers = []
        lastScanCompletedAt = Date()

        if let dao = packageDAO {
            do {
                try dao.replaceAll(with: packages)
                storageWarning = nil
            } catch {
                storageWarning = "Couldn't save the latest scan to the local cache, so it won't be remembered next launch."
            }
        }

        if !packages.isEmpty,
           !UserDefaults.standard.bool(forKey: DefaultsKey.firstScanTaken),
           let sm = snapshotManager {
            _ = try? await sm.capture(packages: packages, reason: .autoFirstScan, note: nil)
            UserDefaults.standard.set(true, forKey: DefaultsKey.firstScanTaken)
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

        // MARK: Provenance collection (gated by user opt-in)
        //
        // This block must remain at the very end of scan(), after packageDAO.replaceAll,
        // so the FK constraint (provenance_evidence.package_id → packages.id) is satisfied.
        //
        // Critical: the guard below is the primary enforcement of "provenance defaults OFF".
        // Nothing outside this block should call the collectors.
        guard provenanceCollection else { return }

        // Require a security-scoped bookmark covering the home directory.
        // The user grants this via "Grant read access…" in Settings → Privacy.
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        guard
            let homePath = folderAccess.grantedPath(forPrefix: homeDir.path),
            let homeBookmarkPair = folderAccess.grantedBookmarks().first(where: { $0.path == homePath })
        else { return }

        // Start security-scoped access for the home directory grant.
        // `startAccessingSecurityScopedResource` is reference-counted: if the
        // same URL was already started in the main scan loop above (because the
        // user also uses the home directory for regular scanning), the count
        // increments to 2 and both `defer` blocks decrement it correctly.
        guard let homeURL = folderAccess.startAccessing(homeBookmarkPair.bookmark) else { return }
        defer { folderAccess.stopAccessing(homeURL) }

        // Run collectors on a background executor. File I/O must stay off the
        // main actor. All captured values are Sendable (URL, [Package]).
        let capturedPackages = packages
        let capturedHomeURL = homeURL
        let evidenceList: [ProvenanceEvidence] = await Task.detached(priority: .utility) {
            ProvenanceCollector(
                shellCollector: ShellHistoryCollector(homeDirectory: capturedHomeURL),
                claudeCodeCollector: ClaudeCodeLogCollector(homeDirectory: capturedHomeURL)
            ).collect(packages: capturedPackages)
        }.value

        // Persist evidence and refresh the in-memory cache. packageDAO.replaceAll
        // already ran above, so FK constraints are satisfied.
        if let dao = provenanceDAO {
            var byId: [String: ProvenanceEvidence] = [:]
            for evidence in evidenceList {
                try? await dao.upsert(evidence)
                byId[evidence.packageId] = evidence
            }
            provenanceByPackageId = byId
        }
    }

    private func scanner(for manager: PackageManager, grantedURLs: [URL]) -> (any PackageScanner)? {
        switch manager {
        case .brew, .brewCask: return BrewScanner()
        case .pip:             return PipScanner(discovery: PythonInterpreterDiscovery(projectVenvRoots: grantedURLs))
        case .pipx:            return PipxScanner()
        case .npm:             return NpmScanner()
        case .cargo:           return CargoScanner()
        case .gem:             return GemScanner()
        case .mas:             return MasScanner(applicationDirectories: grantedApplicationsDirectories(grantedURLs))
        }
    }

    private func grantedApplicationsDirectories(_ grantedRoots: [URL]) -> [URL] {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let candidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeApplications,
        ]

        return candidates.filter { candidate in
            grantedRoots.contains { root in
                let rootPath = root.standardizedFileURL.path
                let candidatePath = candidate.standardizedFileURL.path
                return rootPath == candidatePath || candidatePath.hasPrefix(rootPath + "/")
            }
        }
    }
}
