import Foundation

// MARK: - Score Bucket

/// Describes the data completeness behind a ``CleanupScore``.
///
/// Packages with **both** unknown size and unknown age cannot be meaningfully
/// ranked and land in `.unknown`. They must **not** sort at position zero:
/// "zero score" would mislead — "this scored the minimum, lowest priority" —
/// when the truth is "we have no data at all".
public enum ScoreBucket: String, Sendable, Equatable {
    /// Both age and size contributed to the score.
    case known
    /// Size is unknown; score reflects age only (weight-adjusted).
    case unknownSize
    /// Age is unknown; score reflects size only (weight-adjusted).
    case unknownAge
    /// Both size and age are unknown — the score value is not meaningful.
    case unknown
}

// MARK: - CleanupScore

/// A scored cleanup candidate.
///
/// **Score semantics:** higher = stronger cleanup candidate (old + large).
/// Range is [0, 1] for `.known`, `.unknownSize`, and `.unknownAge` buckets;
/// 0 for `.unknown` (data-less; not a ranked zero).
///
/// **Honesty caveat:** High score = old and/or large, **not** "unused".
/// Installory has no usage telemetry — it cannot detect whether a package is
/// actively called by other processes, scripts, or development environments.
public struct CleanupScore: Sendable, Equatable {
    public let package: Package
    /// Combined cleanup signal. See ``ScoreBucket`` for interpretation.
    public let score: Double
    public let bucket: ScoreBucket

    // MARK: Weights (documented public constants)

    /// Weight applied to the age component. Sums with ``sizeWeight`` to 1.0.
    public static let ageWeight: Double = 0.5
    /// Weight applied to the size component. Sums with ``ageWeight`` to 1.0.
    public static let sizeWeight: Double = 0.5

    public init(package: Package, score: Double, bucket: ScoreBucket) {
        self.package = package
        self.score = score
        self.bucket = bucket
    }
}

extension CleanupScore: Comparable {
    /// `.unknown` entries are always ordered *below* (less than) all other
    /// buckets so they sink to the end of a descending sort.
    /// Within the same knowable category, higher score means greater value.
    public static func < (lhs: CleanupScore, rhs: CleanupScore) -> Bool {
        let lhsUnknown = lhs.bucket == .unknown
        let rhsUnknown = rhs.bucket == .unknown
        if lhsUnknown != rhsUnknown {
            // unknown < everything else
            return lhsUnknown
        }
        return lhs.score < rhs.score
    }
}

// MARK: - Public scoring function

/// Computes cleanup scores for `packages` relative to `now`.
///
/// All clock access is injected via `now` so the function is purely
/// deterministic in tests — no system clock reads occur inside.
///
/// Score formula:
/// ```
/// score = normalizedAge * ageWeight + normalizedSize * sizeWeight
/// ```
/// where `normalizedAge = ageDays / 365 (clamped 0…1)` and
/// `normalizedSize = bytes / 1 GiB (clamped 0…1)`.
///
/// Low-confidence (`Confidence.low` or `.unknown`) ages are down-weighted
/// by 0.5 to avoid over-trusting mtime-derived timestamps.
///
/// - Parameters:
///   - packages: Input packages. Order is not preserved in the result.
///   - now: Reference timestamp for age calculation.
/// - Returns: `[CleanupScore]` sorted highest-score first; `.unknown`-bucket
///   entries are appended at the end.
public func cleanupScores(for packages: [Package], now: Date) -> [CleanupScore] {
    packages
        .map { makeScore(for: $0, now: now) }
        .sorted(by: >)
}

// MARK: - Private helpers

private func makeScore(for pkg: Package, now: Date) -> CleanupScore {
    let ageContrib = ageContribution(for: pkg, now: now)
    let sizeContrib = sizeContribution(for: pkg)

    switch (ageContrib, sizeContrib) {
    case (.none, .none):
        return CleanupScore(package: pkg, score: 0, bucket: .unknown)

    case let (.some(a), .none):
        // Size is unknown: age carries its weight only; score is in [0, 0.5].
        return CleanupScore(
            package: pkg,
            score: a * CleanupScore.ageWeight,
            bucket: .unknownSize
        )

    case let (.none, .some(s)):
        // Age is unknown: size carries its weight only; score is in [0, 0.5].
        return CleanupScore(
            package: pkg,
            score: s * CleanupScore.sizeWeight,
            bucket: .unknownAge
        )

    case let (.some(a), .some(s)):
        return CleanupScore(
            package: pkg,
            score: a * CleanupScore.ageWeight + s * CleanupScore.sizeWeight,
            bucket: .known
        )
    }
}

/// Normalised age contribution in [0, 1], or `nil` if `installedAt` is absent.
///
/// Confidence down-weighting:
/// - `.high`, `.medium` → full weight
/// - `.low`, `.unknown` → multiplied by 0.5 (weak signal, e.g. mtime-only)
private func ageContribution(for pkg: Package, now: Date) -> Double? {
    guard let installedAt = pkg.installedAt else { return nil }
    let ageDays = max(0, now.timeIntervalSince(installedAt) / 86_400)
    var normalized = min(ageDays / 365.0, 1.0)
    switch pkg.installedAtConfidence {
    case .high, .medium:
        break           // full weight
    case .low, .unknown:
        normalized *= 0.5   // down-weight unreliable timestamps
    }
    return normalized
}

/// Normalised size contribution in [0, 1], or `nil` if `sizeBytes` is absent.
private func sizeContribution(for pkg: Package) -> Double? {
    guard let sizeBytes = pkg.sizeBytes else { return nil }
    let oneGiB: Double = 1_073_741_824.0
    return min(Double(sizeBytes) / oneGiB, 1.0)
}
