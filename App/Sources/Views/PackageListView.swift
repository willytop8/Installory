import InstalloryCore
import SwiftUI

struct PackageListView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        Group {
            if coordinator.packages.isEmpty {
                emptyState
            } else if coordinator.filteredPackages.isEmpty && !coordinator.isCleanupMode {
                noMatchState
            } else {
                packageList
            }
        }
        .searchable(text: $coordinator.searchQuery, placement: .toolbar, prompt: "Filter packages")
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                demoBanner
                storageBanner
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            cleanupBottomBar
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !coordinator.isCleanupMode {
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
        }
        .navigationTitle("Packages")
        .onChange(of: coordinator.sortOrder) { _, _ in
            coordinator.persistUIPreferences()
        }
        .onChange(of: coordinator.sidebarSelection) { _, _ in
            coordinator.persistUIPreferences()
        }
    }

    // MARK: - Demo banner

    @ViewBuilder
    private var demoBanner: some View {
        if coordinator.isDemoMode {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text("You're viewing sample data. Nothing here is from your Mac.")
                        .font(.callout)
                    Spacer(minLength: 0)
                    Button("Exit Demo Mode") {
                        coordinator.exitDemoMode()
                    }
                    .buttonStyle(.borderless)
                    .font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.14))
                Divider()
            }
        }
    }

    // MARK: - Storage warning banner

    @ViewBuilder
    private var storageBanner: some View {
        if let warning = coordinator.storageWarning, !coordinator.isDemoMode {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.callout)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .accessibilityElement(children: .combine)
                Divider()
            }
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        if coordinator.isScanning {
            VStack(spacing: 12) {
                ProgressView()
                Text(scanningStatusText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !coordinator.folderAccess.hasAnyGrant {
            ContentUnavailableView {
                Label("No Access Granted", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Grant access to a directory to see what's installed, or explore a pre-populated sample inventory.")
            } actions: {
                exploreSampleDataButton
            }
        } else {
            ContentUnavailableView {
                Label("No Packages Found", systemImage: "shippingbox")
            } description: {
                Text("Installory didn't find any packages in the granted directories. You can explore a pre-populated sample inventory instead.")
            } actions: {
                exploreSampleDataButton
            }
        }
    }

    private var exploreSampleDataButton: some View {
        Button {
            coordinator.enterDemoMode()
        } label: {
            Label("Explore with Sample Data", systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)
        .help("Load a pre-populated sample inventory so you can explore every feature without granting access to any folders.")
    }

    /// Per-manager scan progress for the scanning empty state. Falls back to a
    /// generic message when no managers are currently in flight.
    private var scanningStatusText: String {
        let names = coordinator.inFlightManagers.map(\.displayName).sorted()
        guard !names.isEmpty else { return "Scanning…" }
        return "Scanning \(names.joined(separator: ", "))…"
    }

    private var noMatchState: some View {
        ContentUnavailableView.search(text: coordinator.searchQuery)
    }

    // MARK: - Cleanup bottom bar

    @ViewBuilder
    private var cleanupBottomBar: some View {
        if !coordinator.packages.isEmpty {
            VStack(spacing: 0) {
                Divider()
                if coordinator.isCleanupMode {
                    cleanupModeBar
                } else {
                    selectForCleanupBar
                }
            }
        }
    }

    private var cleanupModeBar: some View {
        HStack(spacing: 8) {
            Button {
                let selected = coordinator.packages.filter { coordinator.selectedForCleanup.contains($0.id) }
                Task { await coordinator.generateAndShowCleanupScript(packages: selected, captureSnapshot: true) }
            } label: {
                Label(
                    "Generate Cleanup Script (\(coordinator.selectedForCleanup.count))",
                    systemImage: "doc.text"
                )
            }
            .disabled(coordinator.selectedForCleanup.isEmpty)
            Spacer()
            Button("Done") {
                coordinator.isCleanupMode = false
                coordinator.selectedForCleanup = []
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var selectForCleanupBar: some View {
        HStack {
            Spacer()
            Button {
                coordinator.isCleanupMode = true
            } label: {
                Label("Select for Cleanup", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Select packages to generate a cleanup script")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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
            PackageRowView(
                package: pkg,
                isCleanupMode: coordinator.isCleanupMode,
                isSelectedForCleanup: coordinator.selectedForCleanup.contains(pkg.id),
                onToggleCleanup: {
                    if coordinator.selectedForCleanup.contains(pkg.id) {
                        coordinator.selectedForCleanup.remove(pkg.id)
                    } else if !pkg.isReadOnly {
                        coordinator.selectedForCleanup.insert(pkg.id)
                    }
                },
                onRemove: (!pkg.isReadOnly && pkg.manager != .mas) ? {
                    Task { await coordinator.requestRemoval([pkg]) }
                } : nil
            )
        }
        .listStyle(.inset)
    }
}

// MARK: - Row

private struct PackageRowView: View {
    let package: Package
    var isCleanupMode: Bool = false
    var isSelectedForCleanup: Bool = false
    var onToggleCleanup: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isCleanupMode {
                if package.isReadOnly {
                    Image(systemName: "lock")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                        .help("Read-only system package — cannot be removed")
                        .accessibilityLabel("Read-only system package, cannot be removed")
                } else {
                    Button {
                        onToggleCleanup?()
                    } label: {
                        Image(systemName: isSelectedForCleanup ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelectedForCleanup ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isSelectedForCleanup ? "Selected for cleanup" : "Not selected for cleanup")
                    .accessibilityHint("Double-tap to toggle whether \(package.name) is included in the cleanup script")
                }
            }
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
        .contextMenu {
            if let onRemove {
                Button("Create Removal Script…", systemImage: "doc.text") {
                    onRemove()
                }
            }
        }
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
