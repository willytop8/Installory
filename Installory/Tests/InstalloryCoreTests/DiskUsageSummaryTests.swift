import Foundation
import InstalloryCore
import Testing

@Suite("Disk usage summary")
struct DiskUsageSummaryTests {
    private func package(
        id: String,
        manager: PackageManager = .brew,
        sizeBytes: Int64?
    ) -> Package {
        Package(
            id: id,
            manager: manager,
            qualifier: nil,
            name: id,
            version: "1.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .unknown,
            sizeBytes: sizeBytes,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_720_000_000)
        )
    }

    @Test("APP-F4: nil and negative sizes are unknown and contribute no bytes")
    func unknownSizesContributeNoBytes() {
        let summary = diskUsageSummary(for: [
            package(id: "nil", sizeBytes: nil),
            package(id: "negative", manager: .npm, sizeBytes: -1),
        ])

        #expect(summary.totalKnownBytes == 0)
        #expect(!summary.totalOverflowed)
        #expect(summary.measuredPackageCount == 0)
        #expect(summary.unknownPackageCount == 2)
        #expect(summary.managers.isEmpty)
        #expect(summary.largestPackages.isEmpty)
    }

    @Test("APP-F4: measured zero remains measured and is not converted to unknown")
    func measuredZeroRemainsMeasured() throws {
        let zero = package(id: "zero", manager: .pip, sizeBytes: 0)
        let summary = diskUsageSummary(for: [zero])

        #expect(summary.totalKnownBytes == 0)
        #expect(summary.measuredPackageCount == 1)
        #expect(summary.unknownPackageCount == 0)
        let manager = try #require(summary.managers.only)
        #expect(manager.manager == .pip)
        #expect(manager.knownBytes == 0)
        #expect(manager.measuredPackageCount == 1)
        #expect(summary.largestPackages == [zero])
    }

    @Test("APP-F4: totals and manager buckets contain each package exactly once")
    func totalsContainEveryPackageOnce() throws {
        let summary = diskUsageSummary(for: [
            package(id: "brew-a", sizeBytes: 10),
            package(id: "brew-b", sizeBytes: 20),
            package(id: "npm-a", manager: .npm, sizeBytes: 7),
            package(id: "unknown", manager: .cargo, sizeBytes: nil),
        ])

        #expect(summary.totalKnownBytes == 37)
        #expect(summary.measuredPackageCount == 3)
        #expect(summary.unknownPackageCount == 1)
        #expect(summary.managers.count == 2)
        let brew = try #require(summary.managers.first { $0.manager == .brew })
        let npm = try #require(summary.managers.first { $0.manager == .npm })
        #expect(brew.knownBytes == 30)
        #expect(brew.measuredPackageCount == 2)
        #expect(npm.knownBytes == 7)
        #expect(npm.measuredPackageCount == 1)
    }

    @Test("APP-F4: manager ordering is bytes descending with a stable manager tie-breaker")
    func managerOrderingIsDeterministic() {
        let summary = diskUsageSummary(for: [
            package(id: "npm-overflow-a", manager: .npm, sizeBytes: .max),
            package(id: "npm-overflow-b", manager: .npm, sizeBytes: 1),
            package(id: "cargo", manager: .cargo, sizeBytes: 10),
            package(id: "brew", manager: .brew, sizeBytes: 10),
            package(id: "pip", manager: .pip, sizeBytes: 1),
        ])

        #expect(summary.managers.map(\.manager) == [.npm, .brew, .cargo, .pip])
        #expect(summary.managers.first?.overflowed == true)
    }

    @Test("APP-F4: largest packages honor the limit, exclude unknowns, and break equal-size ties by ID")
    func largestPackagesAreBoundedAndStable() {
        let a = package(id: "a", sizeBytes: 20)
        let b = package(id: "b", sizeBytes: 20)
        let c = package(id: "c", sizeBytes: 10)
        let unknown = package(id: "unknown", sizeBytes: nil)
        let negative = package(id: "negative", sizeBytes: -3)

        #expect(
            diskUsageSummary(
                for: [unknown, b, negative, c, a],
                largestLimit: 2
            ).largestPackages.map(\.id) == [a.id, b.id]
        )
        #expect(
            diskUsageSummary(for: [a], largestLimit: -1).largestPackages.isEmpty
        )
    }

    @Test("APP-F4: aggregation is deterministic, overflow-safe, and input-immutable")
    func aggregationIsDeterministicAndOverflowSafe() throws {
        let packages = [
            package(id: "max", sizeBytes: .max),
            package(id: "one", sizeBytes: 1),
            package(id: "npm", manager: .npm, sizeBytes: 12),
        ]
        let original = packages
        let forward = diskUsageSummary(for: packages)
        let reversed = diskUsageSummary(for: Array(packages.reversed()))

        #expect(forward == reversed)
        #expect(packages == original)
        #expect(forward.totalOverflowed)
        #expect(forward.totalKnownBytes == .max)
        let brew = try #require(forward.managers.first { $0.manager == .brew })
        #expect(brew.overflowed)
        #expect(brew.knownBytes == .max)
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
