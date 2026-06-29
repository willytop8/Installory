import InstalloryCore
import SwiftUI

/// Displays packages whose provenance was attributed to an AI assistant coding session.
///
/// Visibility is controlled by the sidebar (orchestrator wires the navigation link):
/// the link is hidden when `provenanceCollection == false` or when `aiInstalledPackages`
/// is empty. This view only renders when the user navigated to it, so it always has data.
struct AIInstalledView: View {
    @Environment(AppCoordinator.self) private var coordinator

    /// Packages whose provenance evidence carries a `ClaudeCodeContext`.
    ///
    /// Computed locally so the view works without requiring a separate computed
    /// property on `AppCoordinator` (the orchestrator can add one for sidebar badge
    /// count, but this view is self-contained).
    private var aiInstalledPackages: [Package] {
        coordinator.packages.filter {
            wasInstalledByAIAssistant(coordinator.provenanceByPackageId[$0.id])
        }
    }

    var body: some View {
        if aiInstalledPackages.isEmpty {
            emptyState
        } else {
            packageList
        }
    }

    // MARK: - Package list

    private var packageList: some View {
        List {
            Section {
                explanationHeader
            }
            .selectionDisabled()

            Section {
                ForEach(aiInstalledPackages) { pkg in
                    AIInstalledPackageRow(
                        package: pkg,
                        context: coordinator.provenanceByPackageId[pkg.id]?.claudeCodeContext
                    )
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("AI Installed")
    }

    // MARK: - Header

    private var explanationHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(aiInstalledPackages.count) package\(aiInstalledPackages.count == 1 ? "" : "s") installed during AI coding sessions")
                    .fontWeight(.semibold)
                Text("Based on Claude Code session logs. Absence here doesn\u{2019}t mean a package wasn\u{2019}t AI-installed \u{2014} history may be incomplete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No AI-Attributed Packages", systemImage: "sparkles")
        } description: {
            if !coordinator.provenanceCollection {
                Text("Turn on \u{201C}Trace how packages were installed\u{201D} in Settings \u{2192} Privacy to detect packages installed during AI coding sessions.")
            } else {
                Text("When Installory finds packages installed during Claude Code sessions, they\u{2019}ll appear here.")
            }
        }
    }
}

// MARK: - Package row

private struct AIInstalledPackageRow: View {
    let package: Package
    let context: ProvenanceEvidence.ClaudeCodeContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + manager + AI badge + version
            HStack(spacing: 8) {
                Text(package.name)
                    .fontWeight(.semibold)
                ManagerBadge(manager: package.manager)
                AIBadge()
                Spacer(minLength: 0)
                Text(package.version)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let ctx = context {
                attributionDetail(ctx)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func attributionDetail(_ ctx: ProvenanceEvidence.ClaudeCodeContext) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Looks like this was installed during a Claude Code session")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()

            if let summary = ctx.sessionSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(ctx.bashInvocation)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(ctx.projectPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let ts = ctx.timestamp {
                Text(ts, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - AI badge

/// A subtle badge consistent with `ManagerBadge` styling but indicating
/// AI assistant attribution rather than a package manager.
struct AIBadge: View {
    var body: some View {
        Text("AI")
            .font(.system(.caption2, design: .default, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.15))
            .foregroundStyle(Color.purple)
            .clipShape(Capsule())
            .accessibilityLabel("Installed by AI assistant")
            .accessibilityAddTraits(.isStaticText)
            .help("Installed during an AI coding session")
    }
}

#Preview {
    AIInstalledView()
        .environment(AppCoordinator())
        .frame(width: 400, height: 500)
}
