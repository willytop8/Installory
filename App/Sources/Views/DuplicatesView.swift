import InstalloryCore
import SwiftUI

// MARK: - View

struct DuplicatesView: View {
    @Environment(AppCoordinator.self) private var coordinator

    // MARK: PATH

    /// PATH components at app-launch time, earliest-searched first.
    ///
    /// **Caveat:** A sandboxed GUI app may have a different PATH than the
    /// user's interactive terminal. Results are framed accordingly in the UI.
    private var pathComponents: [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
    }

    // MARK: Grouped data

    private struct GroupedContent {
        let active: [(group: DuplicateGroup, standings: [String: PathStanding])]
        let potential: [(group: DuplicateGroup, standings: [String: PathStanding])]
        let benign: [(group: DuplicateGroup, standings: [String: PathStanding])]
        let multiLocation: [MultiLocationGroup]
    }

    private var grouped: GroupedContent {
        let path = pathComponents
        var active: [(DuplicateGroup, [String: PathStanding])] = []
        var potential: [(DuplicateGroup, [String: PathStanding])] = []
        var benign: [(DuplicateGroup, [String: PathStanding])] = []

        // crossManagerDuplicates() returns groups sorted by name; severity
        // tiers are built with stable name-order preserved within each tier.
        for group in coordinator.duplicateGroups {
            let standings = resolvePathStandings(for: group, path: path)
            switch severity(for: group, standings: standings) {
            case .active:    active.append((group, standings))
            case .potential: potential.append((group, standings))
            case .benign:    benign.append((group, standings))
            }
        }

        return GroupedContent(
            active: active,
            potential: potential,
            benign: benign,
            multiLocation: coordinator.packages.multiLocationInstalls()
        )
    }

    // MARK: Body

    var body: some View {
        @Bindable var coordinator = coordinator
        let data = grouped
        let hasCrossManager = !coordinator.duplicateGroups.isEmpty
        let hasMultiLocation = !data.multiLocation.isEmpty

        if !hasCrossManager && !hasMultiLocation {
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
                // ── Intro text ───────────────────────────────────────────
                if hasCrossManager {
                    Section {
                        Text(
                            "These tools are installed by more than one package manager. " +
                            "That can cause version confusion \u{2014} a command like \u{201C}node\u{201D} " +
                            "resolves to whichever install is first on your PATH. " +
                            "Where we can determine which install is active, " +
                            "you\u{2019}ll see a \u{201C}Wins on PATH\u{201D} badge. " +
                            "This is based on the environment at app launch " +
                            "and may not match your terminal\u{2019}s PATH. " +
                            "Select an install below to open its detail pane and generate a removal script."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                        .selectionDisabled()
                    }
                }

                // ── Active conflicts ─────────────────────────────────────
                if !data.active.isEmpty {
                    Section {
                        ForEach(data.active, id: \.group.name) { entry in
                            Section(entry.group.name) {
                                ForEach(entry.group.packages) { pkg in
                                    DuplicateInstallRow(
                                        package: pkg,
                                        standing: entry.standings[pkg.id] ?? .unknown
                                    )
                                    .tag(pkg.id)
                                }
                            }
                        }
                    } header: {
                        Label("These can cause the wrong version to run",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                // ── Potential conflicts ──────────────────────────────────
                if !data.potential.isEmpty {
                    Section {
                        ForEach(data.potential, id: \.group.name) { entry in
                            Section(entry.group.name) {
                                ForEach(entry.group.packages) { pkg in
                                    DuplicateInstallRow(
                                        package: pkg,
                                        standing: entry.standings[pkg.id] ?? .unknown
                                    )
                                    .tag(pkg.id)
                                }
                            }
                        }
                    } header: {
                        Label("Possible conflicts \u{2014} worth reviewing",
                              systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                }

                // ── Benign groups ────────────────────────────────────────
                if !data.benign.isEmpty {
                    Section {
                        ForEach(data.benign, id: \.group.name) { entry in
                            Section(entry.group.name) {
                                ForEach(entry.group.packages) { pkg in
                                    DuplicateInstallRow(
                                        package: pkg,
                                        standing: entry.standings[pkg.id] ?? .unknown
                                    )
                                    .tag(pkg.id)
                                }
                            }
                        }
                    } header: {
                        Label("Likely harmless \u{2014} tools that share a name",
                              systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Same-manager multi-location installs (informational) ─
                if hasMultiLocation {
                    Section {
                        Text(
                            "These packages appear under multiple interpreters or environments. " +
                            "This is usually fine, but can cause version confusion " +
                            "when different tools pick different installs."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                        .selectionDisabled()

                        ForEach(data.multiLocation, id: \.name) { mlGroup in
                            Section(mlGroup.name) {
                                ForEach(mlGroup.packages) { pkg in
                                    MultiLocationInstallRow(package: pkg)
                                        .tag(pkg.id)
                                }
                            }
                        }
                    } header: {
                        Label("Installed in multiple places (informational)",
                              systemImage: "tray.2")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle("Duplicates")
        }
    }
}

// MARK: - Cross-manager install row

private struct DuplicateInstallRow: View {
    let package: Package
    let standing: PathStanding

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ManagerBadge(manager: package.manager)
                    Text(package.version)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    PathStandingBadge(standing: standing)
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

// MARK: - Multi-location install row

private struct MultiLocationInstallRow: View {
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

// MARK: - PATH standing badge

private struct PathStandingBadge: View {
    let standing: PathStanding

    var body: some View {
        switch standing {
        case .wins:
            Text("Wins on PATH")
                .font(.system(.caption2, design: .default, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(Color.green)
                .clipShape(Capsule())

        case .shadowed:
            Text("Shadowed")
                .font(.system(.caption2, design: .default, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())

        case .unknown:
            EmptyView()
        }
    }
}

// MARK: - Preview

#Preview {
    DuplicatesView()
        .environment(AppCoordinator())
        .frame(width: 380, height: 600)
}
