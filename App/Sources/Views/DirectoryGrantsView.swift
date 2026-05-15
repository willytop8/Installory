import SwiftUI

/// Menu content listing canonical directories not yet granted.
/// Embed inside a `Menu { DirectoryGrantsView() }` in the sidebar.
struct DirectoryGrantsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        let ungrantedDirs = coordinator.ungrantedCanonicalDirectories
        if ungrantedDirs.isEmpty {
            Text("All recommended directories granted")
                .foregroundStyle(.secondary)
        } else {
            ForEach(ungrantedDirs) { dir in
                Button {
                    Task { await coordinator.grantDirectory(suggestedPath: dir.path) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dir.displayPath)
                        Text(dir.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
