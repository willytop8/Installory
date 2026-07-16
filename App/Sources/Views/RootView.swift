import InstalloryCore
import SwiftUI

/// Why a dedicated analysis view has no rows to display.
///
/// A positive "no findings" message is reserved for a completed, successful
/// scan across every supported manager. Saved inventory with unknown coverage,
/// skipped managers, and failed scans remain explicitly inconclusive.
enum AnalysisEmptyState: Equatable {
    case scanInProgress
    case noInventory
    case incompleteCoverage
    case noResults

    static func resolve(
        packageCount: Int,
        isScanning: Bool,
        isDemoMode: Bool,
        scanStatuses: [PackageManager: ScannerStatus]
    ) -> AnalysisEmptyState {
        if isScanning {
            return .scanInProgress
        }
        if isDemoMode {
            return packageCount == 0 ? .noInventory : .noResults
        }

        let hasCompleteCoverage = PackageManager.allCases.allSatisfy { manager in
            guard let status = scanStatuses[manager], case .succeeded = status else {
                return false
            }
            return true
        }
        if !scanStatuses.isEmpty, !hasCompleteCoverage {
            return .incompleteCoverage
        }
        if packageCount == 0 {
            return .noInventory
        }
        return hasCompleteCoverage ? .noResults : .incompleteCoverage
    }
}

/// Sections that can contain shell-removable packages and expose bulk controls.
extension SidebarSelection {
    var supportsCleanupControls: Bool {
        switch self {
        case .all, .manager, .duplicates, .orphans:
            return true
        case .readOnly, .diskUsage, .aiInstalled, .snapshot:
            return false
        }
    }
}

struct AnalysisEmptyStateView: View {
    let state: AnalysisEmptyState
    let noResultsTitle: String
    let noResultsSystemImage: String
    let noResultsDescription: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        }
    }

    private var title: String {
        switch state {
        case .scanInProgress: "Analysis in Progress"
        case .noInventory: "No Package Inventory"
        case .incompleteCoverage: "Results May Be Incomplete"
        case .noResults: noResultsTitle
        }
    }

    private var systemImage: String {
        switch state {
        case .scanInProgress: "arrow.triangle.2.circlepath"
        case .noInventory: "shippingbox"
        case .incompleteCoverage: "exclamationmark.triangle"
        case .noResults: noResultsSystemImage
        }
    }

    private var description: String {
        switch state {
        case .scanInProgress:
            "Installory is still scanning. This analysis will update when the scan finishes."
        case .noInventory:
            "Grant access to a package directory and run a scan before using this analysis."
        case .incompleteCoverage:
            "One or more package managers have not completed a successful scan. Review Scan Coverage and scan again before relying on this analysis."
        case .noResults:
            noResultsDescription
        }
    }
}

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        NavigationSplitView {
            SidebarView()
        } content: {
            if case .snapshot(let id) = coordinator.sidebarSelection {
                SnapshotContentView(snapshotID: id)
            } else if case .duplicates = coordinator.sidebarSelection {
                DuplicatesView()
            } else if case .orphans = coordinator.sidebarSelection {
                OrphansView()
            } else if case .diskUsage = coordinator.sidebarSelection {
                DiskUsageView()
            } else if case .aiInstalled = coordinator.sidebarSelection {
                AIInstalledView()
            } else {
                PackageListView()
            }
        } detail: {
            if case .snapshot = coordinator.sidebarSelection {
                ContentUnavailableView {
                    Label("Snapshot View", systemImage: "camera.viewfinder")
                } description: {
                    Text("Select a package manager section to browse packages in this snapshot.")
                }
            } else if let pkg = coordinator.selectedPackage {
                PackageDetailView(package: pkg)
            } else {
                ContentUnavailableView {
                    Label("No Package Selected", systemImage: "shippingbox")
                } description: {
                    Text("Select a package from the list to view its details.")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    DirectoryGrantsView()
                    Divider()
                    Button("Grant Custom Directory\u{2026}", systemImage: "folder") {
                        Task { await coordinator.grantCustomDirectory() }
                    }
                } label: {
                    Label("Grant Access", systemImage: "folder.badge.plus")
                }
                .help("Grant Installory read access to a folder")
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if coordinator.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        coordinator.isCleanupMode.toggle()
                        if !coordinator.isCleanupMode {
                            coordinator.selectedForCleanup = []
                        }
                    } label: {
                        Label(
                            coordinator.isCleanupMode ? "Exit Cleanup Mode" : "Cleanup Mode",
                            systemImage: coordinator.isCleanupMode ? "checklist.checked" : "checklist"
                        )
                    }
                    .disabled(
                        !coordinator.canEnterCleanupMode
                    )
                    .help(
                        coordinator.canEnterCleanupMode
                            ? "Select packages to generate a cleanup script (⇧⌘K)"
                            : "No packages in this section have a generated removal command"
                    )

                    Button {
                        Task { await coordinator.captureManualSnapshot() }
                    } label: {
                        Label("Snapshot Now", systemImage: "camera.viewfinder")
                    }
                    .help("Capture a manual snapshot of the current inventory")
                    .disabled(coordinator.packages.isEmpty || coordinator.isScanning)

                    Button {
                        Task { await coordinator.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(coordinator.isScanning)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Rescan all granted directories (⌘R)")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 580)
        .task {
            await coordinator.hydratePersistedState()
            await coordinator.autoScanIfNeeded()
        }
        // Persisted here rather than in PackageListView, which unmounts whenever the
        // user navigates to one of the dedicated sections above.
        .onChange(of: coordinator.sidebarSelection) { _, _ in
            coordinator.reconcileCleanupSelectionForCurrentSidebar()
            coordinator.reconcileSelectedPackageForCurrentSidebar()
            coordinator.persistUIPreferences()
        }
        .onChange(of: coordinator.isCleanupMode) { _, _ in
            // Also catches the global keyboard command in a section without a
            // package that can produce a removal command.
            coordinator.reconcileCleanupSelectionForCurrentSidebar()
        }
        .sheet(isPresented: Binding(
            get: { coordinator.cleanupResult != nil },
            set: { if !$0 { coordinator.cleanupResult = nil } }
        )) {
            if let result = coordinator.cleanupResult {
                CleanupScriptSheetView(result: result)
                    .environment(coordinator)
            }
        }
        .sheet(isPresented: Binding(
            get: { coordinator.pendingRemovalPackages != nil },
            set: { if !$0 { coordinator.cancelRemoval() } }
        )) {
            if let packages = coordinator.pendingRemovalPackages {
                SnapshotChoiceSheet(packages: packages)
                    .environment(coordinator)
            }
        }
        .sheet(isPresented: Binding(
            get: { !coordinator.onboardingCompleted },
            set: { _ in }
        )) {
            OnboardingView()
                .environment(coordinator)
        }
        .actionErrorAlert(coordinator: coordinator)
    }

}

extension View {
    /// Surfaces a failed user-initiated action (export, manual snapshot) as an alert.
    /// Applied wherever those actions can be triggered — the main window and Settings.
    func actionErrorAlert(coordinator: AppCoordinator) -> some View {
        alert(
            "Something didn\u{2019}t work",
            isPresented: Binding(
                get: { coordinator.actionError != nil },
                set: { if !$0 { coordinator.dismissActionError() } }
            )
        ) {
            Button("OK", role: .cancel) { coordinator.dismissActionError() }
        } message: {
            if let message = coordinator.actionError {
                Text(message)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppCoordinator())
}
