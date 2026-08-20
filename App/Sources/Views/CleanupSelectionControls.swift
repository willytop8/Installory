import InstalloryCore
import SwiftUI

/// Shared Cleanup Mode footer for every live-inventory section that supports
/// bulk script generation. The coordinator owns the section scope and selection.
struct CleanupSelectionFooter: View {
    @Environment(AppCoordinator.self) private var coordinator

    @ViewBuilder
    var body: some View {
        if coordinator.canEnterCleanupMode {
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
                let selected = coordinator.selectedCleanupPackages
                Task {
                    await coordinator.generateAndShowCleanupScript(
                        packages: selected,
                        captureSnapshot: true
                    )
                }
            } label: {
                Label(
                    "Generate Cleanup Script (\(coordinator.selectedCleanupPackages.count))",
                    systemImage: "doc.text"
                )
            }
            .disabled(coordinator.selectedCleanupPackages.isEmpty)

            Picker("Removal strategy", selection: removalStrategyBinding) {
                Text("Uninstall").tag(RemovalStrategy.uninstall)
                Text("Move to Trash").tag(RemovalStrategy.trash)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Move to Trash keeps file-backed packages recoverable; package-manager installs are always uninstalled properly")

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

    private var removalStrategyBinding: Binding<RemovalStrategy> {
        Binding(
            get: { coordinator.removalStrategy },
            set: { coordinator.removalStrategy = $0 }
        )
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
}

/// Per-row selection affordance shared by Package List, Duplicates, and Review
/// Candidates. It is absent outside Cleanup Mode and never performs removal.
struct CleanupSelectionToggle: View {
    @Environment(AppCoordinator.self) private var coordinator

    let package: Package

    @ViewBuilder
    var body: some View {
        if coordinator.isCleanupMode {
            if package.isRemovalScriptEligible {
                Button {
                    if coordinator.selectedForCleanup.contains(package.id) {
                        coordinator.selectedForCleanup.remove(package.id)
                    } else {
                        coordinator.selectedForCleanup.insert(package.id)
                    }
                } label: {
                    Image(
                        systemName: coordinator.selectedForCleanup.contains(package.id)
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        coordinator.selectedForCleanup.contains(package.id)
                            ? Color.accentColor
                            : Color.secondary
                    )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Toggles whether \(package.name) is included in the generated cleanup script")
                .help("Include \(package.name) in the generated cleanup script")
            } else {
                Image(systemName: "lock")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
                    .accessibilityLabel(ineligibleDescription)
                    .help(ineligibleDescription)
            }
        }
    }

    private var accessibilityLabel: String {
        coordinator.selectedForCleanup.contains(package.id)
            ? "\(package.name), selected for cleanup"
            : "\(package.name), not selected for cleanup"
    }

    private var ineligibleDescription: String {
        if package.manager == .mas {
            return "\(package.name) must be removed manually from Applications"
        }
        return "\(package.name) is a read-only system package and cannot be removed"
    }
}
