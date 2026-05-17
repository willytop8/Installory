import Foundation

/// Renders ``ProvenanceEvidence`` into a human-readable English sentence.
///
/// Template selection is based on which signals are populated in the evidence;
/// the most specific available template is always chosen. No LLM, no network
/// calls — rendering is entirely local string interpolation.
///
/// **Co-installed name lookup:** `render` accepts a `nameByPackageId` dictionary
/// (`[packageId: displayName]`) so the renderer stays free of scanner dependencies.
/// Build it at the call site:
/// ```swift
/// let nameByPackageId = Dictionary(uniqueKeysWithValues: packages.map { ($0.id, $0.name) })
/// ```
/// If a co-installed package id is absent from the dict (stale scan data between
/// collection and rendering), the renderer falls back to the last colon-delimited
/// component of the id string — it never crashes or silently drops the entry.
///
/// **Date formatting:** Dates within the last 14 days are rendered as relative
/// strings ("3 days ago", "yesterday") using `RelativeDateTimeFormatter`. Older
/// dates use an absolute format ("Aug 14, 2025"). Both formatters are created
/// per call — `RelativeDateTimeFormatter` is `@unchecked Sendable` in Swift 6.
public struct NarrativeRenderer: Sendable {
    public init() {}

    /// Renders provenance evidence into a human-readable sentence.
    ///
    /// - Parameters:
    ///   - evidence: The provenance signals for the package.
    ///   - package: The package being described. Passed through for call-site
    ///     symmetry; currently unused inside the renderer because all needed
    ///     identity is already in `evidence`.
    ///   - nameByPackageId: Maps package id → display name for co-installed
    ///     list resolution. Defaults to empty; pass a populated dict for
    ///     human-readable names in the "You also installed…" clause.
    public func render(
        _ evidence: ProvenanceEvidence,
        package: Package,
        nameByPackageId: [String: String] = [:]
    ) -> String {
        let coNames = evidence.coInstalledWithin1h
            .map { displayName(for: $0, in: nameByPackageId) }

        if let context = evidence.claudeCodeContext {
            return renderClaudeCode(context: context, coInstalled: coNames)
        }
        if let command = evidence.installCommand {
            return renderShell(command: command, fsDate: evidence.fsInstallTime, coInstalled: coNames)
        }
        if let date = evidence.fsInstallTime {
            return renderFsOnly(date: date, coInstalled: coNames)
        }
        return "We don't have a recorded install date for this package."
    }

    // MARK: - Template cases

    private func renderClaudeCode(
        context: ProvenanceEvidence.ClaudeCodeContext,
        coInstalled: [String]
    ) -> String {
        let dateStr = context.timestamp.map { formatDate($0) } ?? "an unknown date"
        let summary: String
        if let s = context.sessionSummary {
            summary = " That session was about: \(s)."
        } else if let msg = context.firstUserMessage {
            summary = " You'd asked: \"\(msg)\"."
        } else {
            summary = ""
        }
        return "Installed \(dateStr) while working in \(context.projectPath).\(summary)\(coInstalledClause(coInstalled))"
    }

    private func renderShell(
        command: ProvenanceEvidence.InstallCommandRecord,
        fsDate: Date?,
        coInstalled: [String]
    ) -> String {
        // Prefer the command's own timestamp; fall back to the filesystem date.
        let date = command.timestamp ?? fsDate
        let dateStr = date.map { formatDate($0) } ?? "an unknown date"
        return "Installed \(dateStr) via `\(command.command)` in your terminal.\(coInstalledClause(coInstalled))"
    }

    private func renderFsOnly(date: Date, coInstalled: [String]) -> String {
        "Installed \(formatDate(date)) (based on file timestamp; we don't have a matching install command in your history).\(coInstalledClause(coInstalled))"
    }

    // MARK: - Date formatting

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let elapsed = now.timeIntervalSince(date)
        // Within 14 days and not in the future: relative format.
        if elapsed >= 0 && elapsed < 14 * 24 * 3600 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .named
            return formatter.localizedString(for: date, relativeTo: now)
        }
        // Older (or future): absolute format "Aug 14, 2025".
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Co-installed clause

    private func coInstalledClause(_ names: [String]) -> String {
        guard !names.isEmpty else { return "" }
        return " You also installed \(joinedList(names)) around the same time."
    }

    private func joinedList(_ names: [String]) -> String {
        switch names.count {
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) and \(names[1])"
        default:
            let allButLast = names.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(names.last!)"
        }
    }

    // MARK: - Display name fallback

    /// Returns `lookup[packageId]`, or the last `:` component of `packageId` as a fallback.
    ///
    /// Example fallback: `"pip:/usr/bin/python3:requests"` → `"requests"`.
    private func displayName(for packageId: String, in lookup: [String: String]) -> String {
        lookup[packageId] ?? packageId.split(separator: ":").last.map(String.init) ?? packageId
    }
}
