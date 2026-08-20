import Foundation

/// A ranked set of packages that are safe to remove, plus their combined
/// measured payload.
///
/// "Safe" here has a precise, conservative meaning: the package is eligible
/// for script-based removal, is not denylisted, and nothing depends on it.
/// It is **not** a usage signal — Installory has no usage telemetry, so a
/// high-ranked package is "old and/or large", not "unused".
public struct FreeUpSpaceBundle: Sendable, Equatable {
    /// Highest-score safe-to-remove candidates, sorted highest-first.
    public let candidates: [CleanupScore]
    /// Sum of measured `sizeBytes` across `candidates`. Unknown sizes are
    /// treated as zero (they contribute nothing), never inferred.
    public let totalReclaimableBytes: Int64

    public init(candidates: [CleanupScore]) {
        self.candidates = candidates
        self.totalReclaimableBytes = candidates.reduce(0) {
            $0 + ($1.package.sizeBytes ?? 0)
        }
    }

    public var isEmpty: Bool { candidates.isEmpty }
}

/// Pure functions that turn existing cleanup signals into a single
/// "free up space" bundle.
public enum FreeUpSpace {
    /// Returns the top `limit` safe-to-remove packages ranked by cleanup score.
    ///
    /// A package qualifies when all of the following hold:
    /// - `Package.isRemovalScriptEligible` is true (removable via script),
    /// - it is not in `denylist`,
    /// - no other package depends on it (per `reverseDependencyIndex`), and
    /// - its measured size is greater than zero.
    ///
    /// The function is pure and deterministic: the clock is injected via
    /// `now`, and no filesystem or network I/O occurs.
    public static func bundle(
        packages: [Package],
        now: Date,
        reverseDependencyIndex: ReverseDependencyIndex,
        denylist: Denylist = .default,
        limit: Int = 5
    ) -> FreeUpSpaceBundle {
        let safe = cleanupScores(for: packages, now: now).filter { scored in
            let package = scored.package
            guard package.isRemovalScriptEligible,
                  !denylist.isDenylisted(package),
                  (package.sizeBytes ?? 0) > 0 else {
                return false
            }
            return reverseDependencyIndex.dependents(of: package).isEmpty
        }
        return FreeUpSpaceBundle(candidates: Array(safe.prefix(max(0, limit))))
    }
}
