import InstalloryCore
import SwiftUI

struct DuplicatesView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator
        let groups = coordinator.duplicateGroups

        if groups.isEmpty {
            ContentUnavailableView {
                Label("No Duplicates", systemImage: "checkmark.circle")
            } description: {
                Text("No tools are installed by more than one package manager.")
            }
        } else {
            List(
                selection: Binding(
                    get: { coordinator.selectedPackage?.id },
                    set: { id in
                        coordinator.selectedPackage = id.flatMap { target in
                            coordinator.packages.first { $0.id == target }
                        }
                    }
                )
            ) {
                Section {
                    Text(
                        "These tools are installed by more than one package manager. " +
                        "That can cause version confusion \u{2014} a command like \u{201C}node\u{201D} resolves " +
                        "to whichever install is first on your PATH. " +
                        "Select an install below to open its detail pane and generate a removal script."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
                    .selectionDisabled()
                }

                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.packages) { pkg in
                            DuplicateInstallRow(package: pkg)
                                .tag(pkg.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle("Duplicates")
        }
    }
}

// MARK: - Row

private struct DuplicateInstallRow: View {
    let package: Package

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ManagerBadge(manager: package.manager)
                    Text(package.version)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let qualifier = package.qualifier {
                    Text(qualifier)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let path = package.installPath {
                    Text(path.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    DuplicatesView()
        .environment(AppCoordinator())
        .frame(width: 380, height: 500)
}
