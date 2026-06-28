import InstalloryCore
import Foundation
import Testing

@Suite("Cleanup signal scoring")
struct CleanupSignalsTests {

    // Fixed "now" so all tests are deterministic.
    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    // 365 days before `now` — gives a normalised age of exactly 1.0 (clamped).
    private static let oldDate = Date(timeIntervalSince1970: 1_750_000_000 - 365 * 86_400)

    // 30 days before `now` — normalised age = 30/365 ≈ 0.082.
    private static let recentDate = Date(timeIntervalSince1970: 1_750_000_000 - 30 * 86_400)

    // 1 GiB — gives normalised size of exactly 1.0 (clamped).
    private static let largeSize: Int64 = 1_073_741_824

    // 100 MiB — normalised size = 0.1 (roughly).
    private static let smallSize: Int64 = 107_374_182

    /// Minimal package factory.
    private func pkg(
        name: String = "test",
        manager: PackageManager = .brew,
        installedAt: Date? = nil,
        confidence: Confidence = .high,
        sizeBytes: Int64? = nil
    ) -> Package {
        Package(
            id: "\(manager.rawValue)::\(name)",
            manager: manager,
            qualifier: nil,
            name: name,
            version: "1.0.0",
            installPath: nil,
            installedAt: installedAt,
            installedAtConfidence: confidence,
            sizeBytes: sizeBytes,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Self.now
        )
    }

    // MARK: - Size ranking

    @Test("Larger size ranks above smaller size, all else equal")
    func largerSizeRanksHigher() {
        let big   = pkg(name: "big",   sizeBytes: Self.largeSize)
        let small = pkg(name: "small", sizeBytes: Self.smallSize)
        let scores = cleanupScores(for: [big, small], now: Self.now)
        let names = scores.map(\.package.name)
        // Both have no age data → unknownAge bucket; big has higher size score.
        #expect(names.first == "big")
    }

    @Test("Older install ranks above newer install, all else equal")
    func olderInstallRanksHigher() {
        let old    = pkg(name: "old",    installedAt: Self.oldDate,    confidence: .high)
        let recent = pkg(name: "recent", installedAt: Self.recentDate, confidence: .high)
        let scores = cleanupScores(for: [old, recent], now: Self.now)
        let names = scores.map(\.package.name)
        // Both have no size data → unknownSize bucket; old has higher age score.
        #expect(names.first == "old")
    }

    // MARK: - Bucket assignment

    @Test("nil size → unknownSize bucket; score reflects age only")
    func nilSizeIsUnknownSizeBucket() {
        let p = pkg(name: "ageonly", installedAt: Self.oldDate, confidence: .high, sizeBytes: nil)
        let scores = cleanupScores(for: [p], now: Self.now)
        #expect(scores.count == 1)
        let cs = scores[0]
        #expect(cs.bucket == .unknownSize)
        // Expected score: normalizedAge(1.0) * ageWeight(0.5) = 0.5
        #expect(cs.score == CleanupScore.ageWeight * 1.0)
    }

    @Test("nil installedAt → unknownAge bucket; score reflects size only")
    func nilDateIsUnknownAgeBucket() {
        let p = pkg(name: "sizeonly", installedAt: nil, sizeBytes: Self.largeSize)
        let scores = cleanupScores(for: [p], now: Self.now)
        #expect(scores.count == 1)
        let cs = scores[0]
        #expect(cs.bucket == .unknownAge)
        // Expected score: normalizedSize(1.0) * sizeWeight(0.5) = 0.5
        #expect(cs.score == CleanupScore.sizeWeight * 1.0)
    }

    @Test("Both nil → unknown bucket; score is 0")
    func bothNilIsUnknownBucket() {
        let p = pkg(name: "nothing", installedAt: nil, sizeBytes: nil)
        let scores = cleanupScores(for: [p], now: Self.now)
        #expect(scores.count == 1)
        let cs = scores[0]
        #expect(cs.bucket == .unknown)
        #expect(cs.score == 0)
    }

    @Test("Both date and size known → known bucket")
    func bothKnownIsKnownBucket() {
        let p = pkg(name: "full", installedAt: Self.oldDate, confidence: .high, sizeBytes: Self.largeSize)
        let scores = cleanupScores(for: [p], now: Self.now)
        #expect(scores[0].bucket == .known)
        // Score = 1.0 * 0.5 + 1.0 * 0.5 = 1.0
        #expect(scores[0].score == 1.0)
    }

    // MARK: - Confidence down-weighting

    @Test("Low-confidence age is down-weighted (×0.5) compared to high-confidence same date")
    func lowConfidenceDownWeighted() {
        // Same install date, same size — only confidence differs.
        let highConf = pkg(name: "high", installedAt: Self.oldDate, confidence: .high, sizeBytes: nil)
        let lowConf  = pkg(name: "low",  installedAt: Self.oldDate, confidence: .low,  sizeBytes: nil)

        let scores = cleanupScores(for: [highConf, lowConf], now: Self.now)

        let highScore = scores.first(where: { $0.package.name == "high" })!
        let lowScore  = scores.first(where: { $0.package.name == "low"  })!

        // high: age=1.0 * ageWeight = 0.5
        // low:  age=1.0 * 0.5 (down-weighted) * ageWeight = 0.25
        #expect(highScore.score > lowScore.score)
        #expect(highScore.score == CleanupScore.ageWeight)
        #expect(lowScore.score  == CleanupScore.ageWeight * 0.5)
    }

    @Test("Unknown confidence is also down-weighted (×0.5)")
    func unknownConfidenceDownWeighted() {
        let highConf    = pkg(name: "high",    installedAt: Self.oldDate, confidence: .high,    sizeBytes: nil)
        let unknownConf = pkg(name: "unknown", installedAt: Self.oldDate, confidence: .unknown, sizeBytes: nil)

        let scores = cleanupScores(for: [highConf, unknownConf], now: Self.now)

        let highScore    = scores.first(where: { $0.package.name == "high"    })!
        let unknownScore = scores.first(where: { $0.package.name == "unknown" })!

        #expect(highScore.score > unknownScore.score)
        #expect(unknownScore.score == CleanupScore.ageWeight * 0.5)
    }

    // MARK: - Sort order

    @Test("unknown-bucket entries sort after all other buckets")
    func unknownBucketSortsLast() {
        let known   = pkg(name: "known",   installedAt: Self.recentDate, sizeBytes: Self.smallSize)
        let unknown = pkg(name: "unknown", installedAt: nil,             sizeBytes: nil)
        let scores = cleanupScores(for: [known, unknown], now: Self.now)
        #expect(scores.last!.bucket == .unknown)
    }

    @Test("Deterministic given a fixed now — calling twice gives identical results")
    func deterministicGivenFixedNow() {
        let packages = [
            pkg(name: "a", installedAt: Self.oldDate,    confidence: .high,   sizeBytes: Self.largeSize),
            pkg(name: "b", installedAt: Self.recentDate, confidence: .medium, sizeBytes: Self.smallSize),
            pkg(name: "c", installedAt: nil,             confidence: .high,   sizeBytes: nil),
        ]
        let first  = cleanupScores(for: packages, now: Self.now)
        let second = cleanupScores(for: packages, now: Self.now)
        #expect(first.map(\.package.name) == second.map(\.package.name))
        #expect(first.map(\.score)        == second.map(\.score))
    }

    @Test("Input array is not mutated")
    func inputImmutable() {
        let packages = [
            pkg(name: "x", installedAt: Self.oldDate,    sizeBytes: Self.largeSize),
            pkg(name: "y", installedAt: Self.recentDate, sizeBytes: Self.smallSize),
        ]
        let originalOrder = packages.map(\.name)
        _ = cleanupScores(for: packages, now: Self.now)
        #expect(packages.map(\.name) == originalOrder)
    }

    // MARK: - Combined score formula

    @Test("Combined known score equals (normalizedAge * ageWeight) + (normalizedSize * sizeWeight)")
    func combinedScoreFormula() {
        // 182.5 days old → normalizedAge ≈ 0.5
        let halfYearAgo = Date(timeIntervalSince1970: Self.now.timeIntervalSince1970 - 182.5 * 86_400)
        // 512 MiB → normalizedSize ≈ 0.4773
        let halfGiB: Int64 = 536_870_912
        let p = pkg(name: "mid", installedAt: halfYearAgo, confidence: .high, sizeBytes: halfGiB)
        let scores = cleanupScores(for: [p], now: Self.now)
        let cs = scores[0]
        #expect(cs.bucket == .known)
        let expectedAge  = min(182.5 / 365.0, 1.0) * CleanupScore.ageWeight
        let expectedSize = min(Double(halfGiB) / 1_073_741_824.0, 1.0) * CleanupScore.sizeWeight
        #expect(abs(cs.score - (expectedAge + expectedSize)) < 1e-9)
    }
}
