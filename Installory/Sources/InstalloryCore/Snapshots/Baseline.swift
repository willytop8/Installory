/// Baseline comparison support.
///
/// A baseline is a snapshot payload captured on another Mac (or at another
/// point in time) and imported as JSON. Comparing the live inventory against a
/// baseline reuses the same change-set machinery as snapshot diffing: the
/// baseline is wrapped in a `Snapshot` and fed through `snapshotChanges`.
///
/// - Note: pure value work — no filesystem, process, or network access.
import Foundation

public enum Baseline {
    /// The JSON payload shape expected when importing a baseline file.
    /// `SnapshotPayload` is `Codable` with unknown manager keys skipped, so a
    /// baseline captured by a newer version of Installory remains importable.
    public typealias Payload = SnapshotPayload

    /// Computes what changed between an imported baseline and the live
    /// inventory: packages only on this Mac (`added`), packages only in the
    /// baseline (`removed`), and packages present in both at different
    /// versions (`versionChanged`).
    public static func changes(from baseline: SnapshotPayload, to livePackages: [Package]) -> SnapshotChangeSet {
        snapshotChanges(from: baselineSnapshot(baseline), to: livePackages)
    }

    /// Packages present in the baseline but not on this Mac — the recovery
    /// direction for generating a reinstall script.
    public static func missing(from baseline: SnapshotPayload, to livePackages: [Package]) -> [MissingPackage] {
        snapshotDiff(snapshot: baselineSnapshot(baseline), livePackages: livePackages)
    }

    /// Builds a baseline `Snapshot` from an imported payload.
    static func baselineSnapshot(_ payload: SnapshotPayload) -> Snapshot {
        Snapshot(id: UUID(), createdAt: Date(), reason: .manual, note: nil, payload: payload)
    }
}
