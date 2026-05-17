import InstalloryCore
import SwiftUI

struct SnapshotContentView: View {
    let snapshotID: UUID
    @Environment(AppCoordinator.self) private var coordinator
    @State private var searchQuery = ""

    // Restore flow state — all local; nothing in coordinator changes.
    @State private var missingPackages: [MissingPackage] = []
    @State private var showRestoreChecklist = false
    @State private var showNothingMissingAlert = false

    private var snapshot: Snapshot? {
        coordinator.snapshots.first { $0.id == snapshotID }
    }

    var body: some View {
        if let snapshot {
            snapshotBody(snapshot)
        } else {
            ContentUnavailableView {
                Label("Snapshot Not Found", systemImage: "camera.viewfinder")
            } description: {
                Text("This snapshot may have been deleted.")
            }
        }
    }

    @ViewBuilder
    private func snapshotBody(_ snapshot: Snapshot) -> some View {
        let managers = snapshot.payload.managers.keys
            .sorted { $0.rawValue < $1.rawValue }

        List {
            Section {
                metadataHeader(snapshot)
            }
            .selectionDisabled()

            ForEach(managers, id: \.self) { manager in
                let pkgs = filteredPackages(
                    snapshot.payload.managers[manager] ?? [],
                    query: searchQuery
                )
                if !pkgs.isEmpty {
                    Section(manager.displayName) {
                        ForEach(pkgs) { pkg in
                            SnapshotPackageRowView(package: pkg, manager: manager)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .searchable(text: $searchQuery, prompt: "Filter snapshot")
        .navigationTitle("Snapshot")
        .alert("Nothing Missing", isPresented: $showNothingMissingAlert) {
            Button("OK") {}
        } message: {
            Text("Everything in this snapshot is still installed.")
        }
        .sheet(isPresented: $showRestoreChecklist) {
            RestoreChecklistSheet(snapshot: snapshot, missingPackages: missingPackages)
        }
    }

    // MARK: - Metadata header

    private func metadataHeader(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(snapshotReasonLabel(snapshot.reason), systemImage: "camera.viewfinder")
                    .font(.headline)
                Spacer()
                Button {
                    computeAndShowRestoreFlow(snapshot: snapshot)
                } label: {
                    Label("Restore Missing Packages…", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .disabled(coordinator.packages.isEmpty)
                .help("Diff this snapshot against the current inventory and generate a reinstall script")
                Button {
                    coordinator.sidebarSelection = .all
                } label: {
                    Label("Exit Snapshot", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Return to live inventory")
            }
            Text("Captured \(formattedDate(snapshot.createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            let totalCount = snapshot.payload.managers.values.reduce(0) { $0 + $1.count }
            Text("\(totalCount) packages across \(snapshot.payload.managers.count) manager(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Restore flow

    private func computeAndShowRestoreFlow(snapshot: Snapshot) {
        let missing = snapshotDiff(snapshot: snapshot, livePackages: coordinator.packages)
        if missing.isEmpty {
            showNothingMissingAlert = true
        } else {
            missingPackages = missing
            showRestoreChecklist = true
        }
    }

    // MARK: - Helpers

    private func filteredPackages(_ packages: [SnapshotPackage], query: String) -> [SnapshotPackage] {
        guard !query.isEmpty else { return packages }
        return packages.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func snapshotReasonLabel(_ reason: SnapshotReason) -> String {
        switch reason {
        case .manual: return "Manual Snapshot"
        case .preCleanup: return "Pre-Cleanup Snapshot"
        case .preUninstall: return "Pre-Uninstall Snapshot"
        case .autoFirstScan: return "First Scan Snapshot"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Snapshot package row

private struct SnapshotPackageRowView: View {
    let package: SnapshotPackage
    let manager: PackageManager

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .fontWeight(.semibold)
                    ManagerBadge(manager: manager)
                }
                HStack(spacing: 8) {
                    Text(package.version)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !package.isExplicit {
                        Text("dependency")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            if let qualifier = package.qualifier {
                Text(URL(fileURLWithPath: qualifier).lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Restore checklist sheet

/// Two-step sheet: first shows a checklist of missing packages (all pre-checked);
/// after the user clicks "Generate Reinstall Script", the same sheet surface
/// switches to `ScriptSheetView`. Dismissing from either step closes the sheet.
private struct RestoreChecklistSheet: View {
    let snapshot: Snapshot
    let missingPackages: [MissingPackage]

    @State private var selectedIDs: Set<String>
    @State private var generatedScript: String? = nil
    @Environment(\.dismiss) private var dismiss

    init(snapshot: Snapshot, missingPackages: [MissingPackage]) {
        self.snapshot = snapshot
        self.missingPackages = missingPackages
        _selectedIDs = State(initialValue: Set(missingPackages.map(\.id)))
    }

    var body: some View {
        if let script = generatedScript {
            ScriptSheetView(
                title: "Reinstall Script",
                filename: "installory-reinstall.sh",
                scriptText: script
            )
        } else {
            checklistView
        }
    }

    // MARK: - Checklist

    private var checklistView: some View {
        VStack(alignment: .leading, spacing: 0) {
            checklistHeader
            Divider()
            packageList
            Divider()
            footerBar
        }
        .frame(minWidth: 560, minHeight: 400)
    }

    private var checklistHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Restore Missing Packages")
                .font(.title2)
                .fontWeight(.bold)
            HStack(spacing: 6) {
                Text(snapshotReasonLabel(snapshot.reason))
                Text("·")
                Text("Captured \(formattedDate(snapshot.createdAt))")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text("\(missingPackages.count) package(s) not in current inventory")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var packageList: some View {
        List(missingPackages) { mp in
            HStack(spacing: 10) {
                Button {
                    if selectedIDs.contains(mp.id) {
                        selectedIDs.remove(mp.id)
                    } else {
                        selectedIDs.insert(mp.id)
                    }
                } label: {
                    Image(systemName: selectedIDs.contains(mp.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIDs.contains(mp.id) ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mp.package.name)
                            .fontWeight(.semibold)
                        ManagerBadge(manager: mp.manager)
                    }
                    Text(mp.package.version)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let qualifier = mp.package.qualifier {
                    Text(URL(fileURLWithPath: qualifier).lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
    }

    private var footerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
            Spacer()
            Button {
                let selected = missingPackages.filter { selectedIDs.contains($0.id) }
                let result = ReinstallScriptGenerator().generate(missing: selected)
                generatedScript = result.scriptText
            } label: {
                Label(
                    "Generate Reinstall Script (\(selectedIDs.count))",
                    systemImage: "doc.text"
                )
            }
            .disabled(selectedIDs.isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func snapshotReasonLabel(_ reason: SnapshotReason) -> String {
        switch reason {
        case .manual: return "Manual snapshot"
        case .preCleanup: return "Pre-cleanup snapshot"
        case .preUninstall: return "Pre-uninstall snapshot"
        case .autoFirstScan: return "First scan snapshot"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    SnapshotContentView(snapshotID: UUID())
        .environment(AppCoordinator())
        .frame(width: 380, height: 500)
}
