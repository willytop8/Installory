import BackshelfCore
import SwiftUI

struct PackageListView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        Group {
            if coordinator.packages.isEmpty {
                emptyState
            } else if coordinator.filteredPackages.isEmpty {
                noMatchState
            } else {
                packageList
            }
        }
        .searchable(text: $coordinator.searchQuery, placement: .toolbar, prompt: "Filter packages")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Sort", selection: $coordinator.sortOrder) {
                    ForEach(PackageSortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .help("Sort order")
            }
        }
        .navigationTitle("Packages")
        .onChange(of: coordinator.sortOrder) { _, _ in
            coordinator.persistUIPreferences()
        }
        .onChange(of: coordinator.sidebarSelection) { _, _ in
            coordinator.persistUIPreferences()
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        if coordinator.isScanning {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !coordinator.folderAccess.hasAnyGrant {
            ContentUnavailableView {
                Label("No Access Granted", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Grant access to a directory to see what's installed.")
            }
        } else {
            ContentUnavailableView {
                Label("No Packages Found", systemImage: "shippingbox")
            } description: {
                Text("Backshelf didn't find any packages in the granted directories.")
            }
        }
    }

    private var noMatchState: some View {
        ContentUnavailableView.search(text: coordinator.searchQuery)
    }

    // MARK: - Package list

    private var packageList: some View {
        List(
            coordinator.filteredPackages,
            selection: Binding(
                get: { coordinator.selectedPackage?.id },
                set: { id in
                    coordinator.selectedPackage = id.flatMap { target in
                        coordinator.packages.first { $0.id == target }
                    }
                }
            )
        ) { pkg in
            PackageRowView(package: pkg)
        }
        .listStyle(.inset)
    }
}

// MARK: - Row

private struct PackageRowView: View {
    let package: Package

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    ManagerBadge(manager: package.manager)
                }
                Text(package.version)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let date = package.installedAt {
                Text(installDateText(date))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func installDateText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        if days < 14 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: .now)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    return PackageListView()
        .environment(coordinator)
        .frame(width: 380, height: 500)
}
