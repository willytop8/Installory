import Foundation

/// Pure analysis helpers over discovered project workspaces.
///
/// Staleness is a heuristic: a workspace is "stale" when nothing directly
/// inside it has been modified for a threshold period. The app surfaces this
/// honestly — it does not claim the workspace is unused, only untouched.
public enum ProjectWorkspaceAnalysis {
    /// Workspaces untouched for this long are considered stale (90 days).
    public static let defaultStaleThreshold: TimeInterval = 90 * 24 * 60 * 60

    /// Sorts stale-first (oldest `lastModifiedAt` first). Workspaces with an
    /// unknown modification date sort to the end so known data is not buried.
    public static func sortedByStaleness(
        _ workspaces: [ProjectWorkspace]
    ) -> [ProjectWorkspace] {
        workspaces.sorted { lhs, rhs in
            switch (lhs.lastModifiedAt, rhs.lastModifiedAt) {
            case let (l?, r?): return l < r
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    /// Returns true when the workspace's last modification predates `threshold`.
    public static func isStale(
        _ workspace: ProjectWorkspace,
        now: Date = Date(),
        threshold: TimeInterval = defaultStaleThreshold
    ) -> Bool {
        guard let last = workspace.lastModifiedAt else { return false }
        return now.timeIntervalSince(last) >= threshold
    }
}
