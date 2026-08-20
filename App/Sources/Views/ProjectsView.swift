import InstalloryCore
import SwiftUI

/// Read-only inventory of development projects found under the user's granted
/// project directories, ordered oldest-touched first.
///
/// This is a discovery view only — Installory never modifies, deletes, or
/// "cleans up" project workspaces. Rows offer a single Reveal-in-Finder action.
struct ProjectsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        let workspaces = coordinator.sortedProjectWorkspaces

        Group {
            if workspaces.isEmpty {
                emptyState
            } else {
                workspaceList(workspaces)
            }
        }
        .navigationTitle("Projects")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Projects Found", systemImage: "folder")
        } description: {
            Text(
                "Grant Installory read access to a folder that contains your projects "
                + "(for example ~/Projects), then scan again."
            )
        } actions: {
            Button("Grant Access\u{2026}", systemImage: "folder.badge.plus") {
                Task { await coordinator.grantCustomDirectory() }
            }
        }
    }

    private func workspaceList(_ workspaces: [ProjectWorkspace]) -> some View {
        List {
            Section {
                ForEach(workspaces) { workspace in
                    WorkspaceRow(workspace: workspace) {
                        _ = coordinator.folderAccess.revealGrantedItemInFinder(
                            at: workspace.path
                        )
                    }
                }
            } footer: {
                Text(
                    "Projects are discovered read-only. Installory never deletes "
                    + "or modifies project files."
                )
            }
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: ProjectWorkspace
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kindIcon)
                .foregroundStyle(kindColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(kindLabel)
                    if let size = sizeLabel {
                        Text("\u{00B7} \(size)")
                    }
                    if let touched = touchedLabel {
                        Text("\u{00B7} touched \(touched)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Reveal in Finder", systemImage: "folder") {
                reveal()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Reveal \(workspace.name) in Finder")
        }
        .padding(.vertical, 2)
    }

    private var kindIcon: String {
        switch workspace.kind {
        case .node:    "curlybraces.square"
        case .python:  "chevron.left.forwardslash.chevron.right"
        case .rust:    "gearshape.2"
        case .xcode:   "hammer"
        case .git:     "point.3.connected.trianglepath.dotted"
        }
    }

    private var kindLabel: String {
        switch workspace.kind {
        case .node:    "Node.js"
        case .python:  "Python"
        case .rust:    "Rust"
        case .xcode:   "Xcode"
        case .git:     "Git repository"
        }
    }

    private var kindColor: Color {
        switch workspace.kind {
        case .node:    .green
        case .python:  .blue
        case .rust:    .orange
        case .xcode:   .indigo
        case .git:     .secondary
        }
    }

    private var sizeLabel: String? {
        guard let bytes = workspace.sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var touchedLabel: String? {
        guard let date = workspace.lastModifiedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    let coordinator = AppCoordinator()
    coordinator.enterDemoMode()
    coordinator.sidebarSelection = .projects
    return ProjectsView()
        .environment(coordinator)
        .frame(width: 620, height: 700)
}
