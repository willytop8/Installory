import Foundation

public extension SnapshotReason {
    /// Title-case display label used in the sidebar and snapshot views.
    var displayName: String {
        switch self {
        case .manual:        "Manual Snapshot"
        case .preCleanup:    "Pre-Cleanup (Batch)"
        case .preUninstall:  "Pre-Uninstall (Single)"
        case .autoFirstScan: "First Scan"
        }
    }

    /// One-line explanation suitable for tooltips.
    var helpText: String {
        switch self {
        case .manual:
            "Captured manually from the toolbar."
        case .preCleanup:
            "Captured automatically before a batch cleanup script was generated."
        case .preUninstall:
            "Captured automatically before a single-package removal script was generated."
        case .autoFirstScan:
            "Captured automatically the first time Installory found packages."
        }
    }
}
