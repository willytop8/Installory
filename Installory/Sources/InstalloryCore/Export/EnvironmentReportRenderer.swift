import Foundation

/// Renders a shareable Markdown environment report from already-computed inputs.
///
/// Pure: takes no closure over I/O, returns a deterministic String given the same
/// inputs. The caller passes `now` so the generation timestamp is injected rather
/// than captured from the system clock.
///
/// No network, no filesystem, no process execution. Complies with the app sandbox.
public struct EnvironmentReportRenderer: Sendable {
    public init() {}

    /// Renders the report.
    ///
    /// - Parameters:
    ///   - packages:        The full live package inventory.
    ///   - duplicateGroups: Already-computed cross-manager duplicate groups.
    ///   - orphans:         Explicit leaf packages (no in-inventory dependents).
    ///   - now:             Reference timestamp for the generation header.
    ///   - cleanupSignals:  If non-empty, a "Largest / Oldest" section is included.
    ///                      Defaults to `[]` so callers that don't have cleanup scores
    ///                      can omit the parameter.
    public func render(
        packages: [Package],
        duplicateGroups: [DuplicateGroup],
        orphans: [Package],
        now: Date,
        cleanupSignals: [CleanupScore] = []
    ) -> String {
        var lines: [String] = []

        // ── Section 1: Title + timestamp ─────────────────────────────────────
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        lines += [
            "# Installory Environment Report",
            "",
            "Generated: \(iso.string(from: now))",
            "",
        ]

        // ── Section 2: Overview ───────────────────────────────────────────────
        lines += [
            "## Overview",
            "",
            "| Manager | Packages |",
            "| --- | ---: |",
        ]
        let grouped = Dictionary(grouping: packages, by: \.manager)
            .sorted { $0.key.rawValue < $1.key.rawValue }
        for (manager, pkgs) in grouped {
            lines.append("| \(manager.rawValue) | \(pkgs.count) |")
        }
        lines.append("| **Total** | **\(packages.count)** |")
        lines.append("")

        // ── Section 3: Cross-Manager Duplicates ───────────────────────────────
        lines.append("## Cross-Manager Duplicates")
        lines.append("")
        if duplicateGroups.isEmpty {
            lines.append("No cross-manager duplicates found.")
        } else {
            for group in duplicateGroups {
                // Deduplicate manager names (brew+brewCask are already distinct raw values)
                let rawManagers = Array(Set(group.packages.map { $0.manager.rawValue })).sorted()
                lines.append("- \(mdCell(group.name)) (\(rawManagers.joined(separator: ", ")))")
            }
        }
        lines.append("")

        // ── Section 4: Packages to Review (orphans) ───────────────────────────
        lines.append("## Packages to Review")
        lines.append("")
        if orphans.isEmpty {
            lines.append("No explicit leaf packages found.")
        } else {
            for pkg in orphans.sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }) {
                lines.append("- \(mdCell(pkg.name)) (\(pkg.manager.rawValue))")
            }
        }
        lines.append("")

        // ── Section 5 (optional): Largest / Oldest ────────────────────────────
        if !cleanupSignals.isEmpty {
            lines.append("## Largest / Oldest")
            lines.append("")
            lines.append("Top candidates by size and age. High score = old and/or large \u{2014} not necessarily unused.")
            lines.append("")
            lines.append("| Name | Manager | Score |")
            lines.append("| --- | --- | --- |")
            for cs in cleanupSignals.prefix(10) {
                let score = String(format: "%.2f", cs.score)
                lines.append("| \(mdCell(cs.package.name)) | \(cs.package.manager.rawValue) | \(score) |")
            }
            lines.append("")
        }

        // ── Section 6: Full Inventory ─────────────────────────────────────────
        lines.append("## Full Inventory")
        lines.append("")
        appendInventoryTable(to: &lines, packages: packages, now: now)

        return lines.joined(separator: "\n")
    }

    // MARK: - Full inventory table (replicated from InventoryExporter to keep now-injection clean)

    private func appendInventoryTable(to lines: inout [String], packages: [Package], now: Date) {
        // Summary counts by manager
        let grouped = Dictionary(grouping: packages, by: \.manager)
            .sorted { $0.key.rawValue < $1.key.rawValue }

        lines += [
            "| Manager | Packages |",
            "| --- | ---: |",
        ]
        for (manager, pkgs) in grouped {
            lines.append("| \(manager.rawValue) | \(pkgs.count) |")
        }
        lines.append("| **Total** | **\(packages.count)** |")
        lines.append("")

        // Per-manager package tables
        for (manager, pkgs) in grouped {
            lines.append("### \(manager.rawValue) (\(pkgs.count))")
            lines.append("")
            lines.append("| Name | Version | Installed | Path |")
            lines.append("| --- | --- | --- | --- |")
            for pkg in pkgs.sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }) {
                let installed: String
                if let date = pkg.installedAt {
                    installed = date.formatted(date: .abbreviated, time: .omitted)
                } else {
                    installed = "\u{2014}"
                }
                let path = pkg.installPath?.path ?? "\u{2014}"
                lines.append("| \(mdCell(pkg.name)) | \(mdCell(pkg.version)) | \(installed) | \(mdCell(path)) |")
            }
            lines.append("")
        }
    }

    // MARK: - Markdown cell escaping

    /// Escapes characters that would break a GitHub-flavoured Markdown pipe table.
    ///
    /// Escapes both `|` (column separator) and `` ` `` (backtick, avoids unintended
    /// inline-code spans that can confuse renderers). Newlines are collapsed to spaces
    /// so cells remain single-line.
    private func mdCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
