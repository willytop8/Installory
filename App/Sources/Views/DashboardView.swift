import InstalloryCore
import SwiftUI

/// The default landing view. Surfaces big, actionable numbers that each jump
/// straight to the analysis that explains them. Read-only: every card reads an
/// existing aggregate from the coordinator.
struct DashboardView: View {
    @Environment(AppCoordinator.self) private var coordinator

    private var aiInstalledThisWeek: Int {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return coordinator.aiInstalledPackages.filter { pkg in
            guard let installedAt = pkg.installedAt else { return false }
            return installedAt >= cutoff
        }.count
    }

    var body: some View {
        Group {
            if coordinator.packages.isEmpty {
                emptyState
            } else {
                dashboard
            }
        }
        .navigationTitle("Home")
    }

    private var dashboard: some View {
        let bundle = coordinator.freeUpSpaceBundle
        let brokenCount = coordinator.agentStackAnalysis.brokenSymlinkCount
            + coordinator.agentStackAnalysis.missingManifestCount

        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 230), spacing: 12)],
                spacing: 12
            ) {
                StatCard(
                    title: "Packages tracked",
                    value: "\(coordinator.packages.count)",
                    systemImage: "shippingbox",
                    tint: .blue
                ) {
                    coordinator.sidebarSelection = .all
                }

                StatCard(
                    title: "Measured payload",
                    value: byteLabel(coordinator.diskUsageSummary.totalKnownBytes),
                    systemImage: "chart.bar.xaxis",
                    tint: .indigo
                ) {
                    coordinator.sidebarSelection = .diskUsage
                }

                if !bundle.isEmpty {
                    StatCard(
                        title: "Safe to free up",
                        value: byteLabel(bundle.totalReclaimableBytes),
                        subtitle: "\(bundle.candidates.count) \(bundle.candidates.count == 1 ? "package" : "packages")",
                        systemImage: "sparkles",
                        tint: .green
                    ) {
                        coordinator.sidebarSelection = .diskUsage
                    }
                }

                if aiInstalledThisWeek > 0 {
                    StatCard(
                        title: "AI installed this week",
                        value: "\(aiInstalledThisWeek)",
                        systemImage: "sparkle",
                        tint: .pink
                    ) {
                        coordinator.sidebarSelection = .aiInstalled
                    }
                }

                let orphanCount = coordinator.orphanedPackages.count
                if orphanCount > 0 {
                    StatCard(
                        title: "Review candidates",
                        value: "\(orphanCount)",
                        systemImage: "leaf.circle",
                        tint: .orange
                    ) {
                        coordinator.sidebarSelection = .orphans
                    }
                }

                let duplicateCount = coordinator.duplicateGroups.count
                if duplicateCount > 0 {
                    StatCard(
                        title: "Duplicates",
                        value: "\(duplicateCount)",
                        systemImage: "doc.on.doc",
                        tint: .purple
                    ) {
                        coordinator.sidebarSelection = .duplicates
                    }
                }

                if brokenCount > 0 {
                    StatCard(
                        title: "Broken skills",
                        value: "\(brokenCount)",
                        systemImage: "link.badge.plus",
                        tint: .red
                    ) {
                        coordinator.sidebarSelection = .skills
                    }
                }
            }
            .padding(20)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Welcome to Installory", systemImage: "shippingbox")
        } description: {
            Text("Grant Installory read access to a package directory, then run a scan to see what's installed on this Mac.")
        } actions: {
            Button("Grant Access") {
                Task { await coordinator.grantCustomDirectory() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }
}

#Preview {
    let coordinator = AppCoordinator()
    coordinator.enterDemoMode()
    coordinator.sidebarSelection = .dashboard
    return DashboardView()
        .environment(coordinator)
        .frame(width: 640, height: 620)
}
