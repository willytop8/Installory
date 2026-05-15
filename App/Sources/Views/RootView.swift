import SwiftUI

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        NavigationSplitView {
            SidebarView()
        } content: {
            PackageListView()
        } detail: {
            if let pkg = coordinator.selectedPackage {
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
    }
}

#Preview {
    RootView()
        .environment(AppCoordinator())
}
