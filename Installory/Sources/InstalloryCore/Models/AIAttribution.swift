import Foundation

/// Returns `true` when `evidence` indicates the package was installed during an AI assistant
/// coding session.
///
/// **Absence of evidence ≠ not AI-installed.** History may be truncated, provenance may be
/// off, or the package may predate collection. Only call this with evidence that was
/// actively collected; a `nil` argument simply means "unknown."
///
/// Claude Code is the only tracked source today. The predicate is named for the concept
/// ("AI assistant") rather than the specific tool so that future sources (e.g., Cursor,
/// Copilot agents) can map in without a user-visible rename.
///
/// Pure: no I/O, no side effects, deterministic.
public func wasInstalledByAIAssistant(_ evidence: ProvenanceEvidence?) -> Bool {
    evidence?.claudeCodeContext != nil
}
