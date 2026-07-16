import Foundation

/// Measured logical package payload for one package manager.
public struct ManagerDiskUsage: Sendable, Equatable {
    public let manager: PackageManager
    public let knownBytes: Int64
    public let overflowed: Bool
    public let measuredPackageCount: Int

    public init(
        manager: PackageManager,
        knownBytes: Int64,
        overflowed: Bool,
        measuredPackageCount: Int
    ) {
        self.manager = manager
        self.knownBytes = knownBytes
        self.overflowed = overflowed
        self.measuredPackageCount = measuredPackageCount
    }
}

/// A truthful inventory-wide view of sizes that bounded scanners completed.
/// Unknown or invalid values are counted but never inferred as zero.
public struct DiskUsageSummary: Sendable, Equatable {
    public let totalKnownBytes: Int64
    public let totalOverflowed: Bool
    public let measuredPackageCount: Int
    public let unknownPackageCount: Int
    public let managers: [ManagerDiskUsage]
    public let largestPackages: [Package]

    public init(
        totalKnownBytes: Int64,
        totalOverflowed: Bool,
        measuredPackageCount: Int,
        unknownPackageCount: Int,
        managers: [ManagerDiskUsage],
        largestPackages: [Package]
    ) {
        self.totalKnownBytes = totalKnownBytes
        self.totalOverflowed = totalOverflowed
        self.measuredPackageCount = measuredPackageCount
        self.unknownPackageCount = unknownPackageCount
        self.managers = managers
        self.largestPackages = largestPackages
    }
}

private struct MutableManagerDiskUsage {
    var knownBytes: Int64 = 0
    var overflowed = false
    var measuredPackageCount = 0

    mutating func add(_ bytes: Int64) {
        measuredPackageCount += 1
        guard !overflowed else { return }
        let (sum, didOverflow) = knownBytes.addingReportingOverflow(bytes)
        if didOverflow {
            knownBytes = .max
            overflowed = true
        } else {
            knownBytes = sum
        }
    }
}

/// Aggregates only already-recorded package sizes. This is a pure in-memory
/// presentation operation and performs no filesystem, clock, process, network,
/// or persistence access.
public func diskUsageSummary(
    for packages: [Package],
    largestLimit: Int = 10
) -> DiskUsageSummary {
    var totalKnownBytes: Int64 = 0
    var totalOverflowed = false
    var measuredPackageCount = 0
    var unknownPackageCount = 0
    var managerBuckets: [PackageManager: MutableManagerDiskUsage] = [:]
    var measuredPackages: [Package] = []
    managerBuckets.reserveCapacity(PackageManager.allCases.count)
    measuredPackages.reserveCapacity(packages.count)

    for package in packages {
        guard let bytes = package.sizeBytes, bytes >= 0 else {
            unknownPackageCount += 1
            continue
        }

        measuredPackageCount += 1
        measuredPackages.append(package)
        managerBuckets[package.manager, default: MutableManagerDiskUsage()].add(bytes)

        if !totalOverflowed {
            let (sum, didOverflow) = totalKnownBytes.addingReportingOverflow(bytes)
            if didOverflow {
                totalKnownBytes = .max
                totalOverflowed = true
            } else {
                totalKnownBytes = sum
            }
        }
    }

    let managers = managerBuckets.map { manager, bucket in
        ManagerDiskUsage(
            manager: manager,
            knownBytes: bucket.knownBytes,
            overflowed: bucket.overflowed,
            measuredPackageCount: bucket.measuredPackageCount
        )
    }.sorted { lhs, rhs in
        if lhs.overflowed != rhs.overflowed {
            return lhs.overflowed
        }
        if lhs.knownBytes != rhs.knownBytes {
            return lhs.knownBytes > rhs.knownBytes
        }
        return lhs.manager.rawValue < rhs.manager.rawValue
    }

    let limit = max(0, largestLimit)
    let largestPackages = measuredPackages.sorted { lhs, rhs in
        // Only non-negative, non-nil packages enter measuredPackages.
        let lhsBytes = lhs.sizeBytes ?? 0
        let rhsBytes = rhs.sizeBytes ?? 0
        if lhsBytes != rhsBytes {
            return lhsBytes > rhsBytes
        }
        return lhs.id < rhs.id
    }.prefix(limit)

    return DiskUsageSummary(
        totalKnownBytes: totalKnownBytes,
        totalOverflowed: totalOverflowed,
        measuredPackageCount: measuredPackageCount,
        unknownPackageCount: unknownPackageCount,
        managers: managers,
        largestPackages: Array(largestPackages)
    )
}
