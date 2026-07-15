import Foundation

/// Merges one scanner result into the last known inventory without converting
/// a failed, skipped, or timed-out scan into false package removals.
public enum ScanInventoryReconciler {
    /// Replaces the scanner's managed partitions only after a successful scan.
    ///
    /// A successful empty result authoritatively clears those partitions. Every
    /// non-success status preserves the last-known packages until a later scan
    /// can observe the filesystem successfully.
    public static func reconcile(
        existing: [Package],
        scanned: [Package],
        managedManagers: Set<PackageManager>,
        status: ScannerStatus
    ) -> [Package] {
        guard case .succeeded = status else { return existing }

        let preserved = existing.filter { !managedManagers.contains($0.manager) }
        let replacements = scanned.filter { managedManagers.contains($0.manager) }
        return preserved + replacements
    }
}
