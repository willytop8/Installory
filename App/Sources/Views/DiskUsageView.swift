import Charts
import InstalloryCore
import SwiftUI

/// Explains the logical package payload already measured by bounded scanners.
/// Opening this view performs no filesystem work and never treats missing sizes
/// as zero or as reclaimable disk space.
struct DiskUsageView: View {
    @Environment(AppCoordinator.self) private var coordinator

    private var analysisEmptyState: AnalysisEmptyState {
        AnalysisEmptyState.resolve(
            packageCount: coordinator.packages.count,
            isScanning: coordinator.isScanning,
            isDemoMode: coordinator.isDemoMode,
            scanStatuses: coordinator.scanStatuses
        )
    }

    var body: some View {
        let summary = coordinator.diskUsageSummary

        Group {
            if coordinator.packages.isEmpty {
                AnalysisEmptyStateView(
                    state: analysisEmptyState,
                    noResultsTitle: "No Measured Package Payload",
                    noResultsSystemImage: "chart.bar.xaxis",
                    noResultsDescription: "Run a package scan before reviewing measured payload."
                )
            } else if summary.measuredPackageCount == 0 {
                sizeUnavailableState(summary)
            } else {
                usageList(summary)
            }
        }
        .navigationTitle("Disk Usage")
        .onChange(of: summary.largestPackages.map(\.id)) { _, visibleIDs in
            guard let selectedID = coordinator.selectedPackage?.id,
                  !visibleIDs.contains(selectedID) else {
                return
            }
            coordinator.selectedPackage = nil
        }
    }

    private func usageList(_ summary: DiskUsageSummary) -> some View {
        List(selection: selectedPackageID) {
            Section {
                payloadSummary(summary)
                    .selectionDisabled()
            }

            if summary.totalKnownBytes > 0 || summary.totalOverflowed {
                Section("Measured payload by package manager") {
                    managerChart(summary.managers)
                        .frame(minHeight: chartHeight(for: summary.managers.count))
                        .selectionDisabled()
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("0 Bytes Measured", systemImage: "shippingbox")
                    } description: {
                        Text("Measured packages contain no logical file bytes. Unknown packages, if any, remain excluded.")
                    }
                    .selectionDisabled()
                }
            }

            Section("Largest measured packages") {
                ForEach(summary.largestPackages) { package in
                    largestPackageRow(package)
                        .tag(package.id)
                        .contextMenu {
                            PackageContextMenu(package: package)
                        }
                }
            }
        }
        .listStyle(.inset)
    }

    private var selectedPackageID: Binding<Package.ID?> {
        Binding(
            get: { coordinator.selectedPackage?.id },
            set: { id in
                coordinator.selectedPackage = id.flatMap(coordinator.package(id:))
            }
        )
    }

    private func payloadSummary(_ summary: DiskUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Measured package payload")
                        .font(.headline)
                    Text(totalLabel(summary))
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Measured package payload, \(totalLabel(summary))")
                }
                Spacer(minLength: 12)
                if coordinator.isScanning {
                    Label("Updating", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Package measurements are updating")
                }
            }

            Text("\(summary.measuredPackageCount) of \(coordinator.packages.count) packages measured")
                .font(.callout)
                .foregroundStyle(.secondary)

            if summary.unknownPackageCount > 0 {
                Label {
                    Text("Totals exclude \(summary.unknownPackageCount) \(packageWord(summary.unknownPackageCount)) whose bounded size measurement was unavailable.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Text("Logical package payload can differ from Finder or Disk Utility and is not a promise of reclaimable space.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func sizeUnavailableState(_ summary: DiskUsageSummary) -> some View {
        ContentUnavailableView {
            Label("Size Data Unavailable", systemImage: "chart.bar.xaxis")
        } description: {
            Text("0 of \(coordinator.packages.count) packages measured. Bounded scans could not complete size measurement for \(summary.unknownPackageCount) \(packageWord(summary.unknownPackageCount)), so Installory will not present them as zero bytes.")
        }
    }

    private func managerChart(_ usages: [ManagerDiskUsage]) -> some View {
        Chart(usages, id: \.manager) { usage in
            BarMark(
                x: .value("Measured bytes", usage.knownBytes),
                y: .value("Package manager", usage.manager.displayName)
            )
            .foregroundStyle(usage.manager.badgeColor)
            .annotation(position: .trailing, alignment: .leading) {
                Text(managerValueLabel(usage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(usage.manager.displayName)
            .accessibilityValue(managerAccessibilityValue(usage))
        }
        .chartYScale(domain: usages.map { $0.manager.displayName })
        .chartXAxisLabel("Measured logical bytes")
        .accessibilityLabel("Measured package payload by manager")
        .padding(.trailing, 130)
    }

    private func largestPackageRow(_ package: Package) -> some View {
        HStack(spacing: 8) {
            Text(package.name)
                .fontWeight(.semibold)
                .lineLimit(1)
                .help(package.name)
            ManagerBadge(manager: package.manager)
            Spacer(minLength: 8)
            Text(byteLabel(package.sizeBytes ?? 0))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Measured payload \(byteLabel(package.sizeBytes ?? 0))")
        }
        .padding(.vertical, 2)
    }

    private func totalLabel(_ summary: DiskUsageSummary) -> String {
        summary.totalOverflowed
            ? "Exceeds supported display range"
            : byteLabel(summary.totalKnownBytes)
    }

    private func managerValueLabel(_ usage: ManagerDiskUsage) -> String {
        usage.overflowed
            ? "Exceeds supported display range"
            : byteLabel(usage.knownBytes)
    }

    private func managerAccessibilityValue(_ usage: ManagerDiskUsage) -> String {
        "\(managerValueLabel(usage)) across \(usage.measuredPackageCount) measured \(packageWord(usage.measuredPackageCount))"
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func packageWord(_ count: Int) -> String {
        count == 1 ? "package" : "packages"
    }

    private func chartHeight(for managerCount: Int) -> CGFloat {
        max(180, CGFloat(managerCount) * 38)
    }
}

#Preview {
    let coordinator = AppCoordinator()
    coordinator.enterDemoMode()
    coordinator.sidebarSelection = .diskUsage
    return DiskUsageView()
        .environment(coordinator)
        .frame(width: 620, height: 700)
}
