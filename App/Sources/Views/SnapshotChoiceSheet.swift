import InstalloryCore
import SwiftUI

/// Presented by RootView when the snapshot preference is `.ask` and the user
/// has initiated a per-package removal. One sheet, one code path — both the
/// detail-pane button and the context menu route here via AppCoordinator.
struct SnapshotChoiceSheet: View {
    let packages: [Package]
    @Environment(AppCoordinator.self) private var coordinator
    @State private var rememberChoice = false

    private var packageNames: String {
        switch packages.count {
        case 1:
            return packages[0].name
        case 2:
            return "\(packages[0].name) and \(packages[1].name)"
        default:
            return "\(packages[0].name) and \(packages.count - 1) others"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Take a snapshot before generating a removal script for \(packageNames)?")
                    .font(.headline)
                Text("A snapshot lets you restore these packages later using Installory\u{2019}s \u{201C}Restore Missing Packages\u{201D} flow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Remember my choice", isOn: $rememberChoice)

            Text("You can change this at any time in Installory › Settings…")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            HStack(spacing: 10) {
                Button("Skip Snapshot") {
                    Task {
                        await coordinator.confirmRemoval(
                            packages: packages,
                            takeSnapshot: false,
                            remember: rememberChoice
                        )
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)

                Spacer()

                Button("Take Snapshot") {
                    Task {
                        await coordinator.confirmRemoval(
                            packages: packages,
                            takeSnapshot: true,
                            remember: rememberChoice
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
