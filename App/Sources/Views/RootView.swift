import SwiftUI

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
                    .disabled(coordinator.packages.isEmpty)
                    .help("Select packages to generate a cleanup script (⇧⌘K)")

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
            await coordinator.autoScanIfNeeded()
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
    }
}

#Preview {
    RootView()
        .environment(AppCoordinator())
}
