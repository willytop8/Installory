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
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if coordinator.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
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
