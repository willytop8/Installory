import BackshelfCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        List(selection: $coordinator.sidebarSelection) {
            packageManagerSection
            directoryAccessSection
        }
        .listStyle(.sidebar)
        .navigationTitle("Backshelf")
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    // MARK: - Sections

    private var packageManagerSection: some View {
        Section("Package Managers") {
            NavigationLink(value: SidebarSelection.all) {
                Label("All packages (\(coordinator.packages.count))", systemImage: "tray.full")
            }

            ForEach(visibleManagers, id: \.self) { manager in
                let count = coordinator.packages.filter { $0.manager == manager }.count
                NavigationLink(value: SidebarSelection.manager(manager)) {
                    Label("\(manager.displayName) (\(count))", systemImage: manager.sidebarSymbol)
                }
            }

            let readOnlyCount = coordinator.packages.filter(\.isReadOnly).count
            if readOnlyCount > 0 {
                NavigationLink(value: SidebarSelection.readOnly) {
                    Label("Read-only (\(readOnlyCount))", systemImage: "lock")
                }
            }
        }
    }

    @ViewBuilder
    private var directoryAccessSection: some View {
        Section("Directory Access") {
            let granted = coordinator.grantedDirectories
            if granted.isEmpty {
                Text("No directories granted")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .selectionDisabled()
            } else {
                ForEach(granted) { dir in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dir.displayPath)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Text(dir.managersUnlocked)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .selectionDisabled()
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(coordinator.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Menu {
                    DirectoryGrantsView()
                } label: {
                    Label("Grant Recommended ▾", systemImage: "folder.badge.plus")
                        .font(.callout)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .help("Grant access to a recommended directory")

                Spacer(minLength: 0)

                Button {
                    Task { await coordinator.grantCustomDirectory() }
                } label: {
                    Label("Custom…", systemImage: "folder")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Grant access to a custom directory")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Helpers

    private var visibleManagers: [PackageManager] {
        let seen = Set(coordinator.packages.map(\.manager))
        return PackageManager.allCases.filter { seen.contains($0) }
    }
}

#Preview {
    NavigationSplitView {
        SidebarView()
    } content: {
        Text("List")
    } detail: {
        Text("Detail")
    }
    .environment(AppCoordinator())
    .frame(width: 900, height: 600)
}
