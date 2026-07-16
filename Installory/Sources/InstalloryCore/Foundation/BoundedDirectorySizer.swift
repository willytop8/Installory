import Foundation

struct DirectorySizeLimits: Sendable, Equatable {
    let maxEntriesPerMeasurement: Int
    let maxBytesPerMeasurement: Int64
    let maxDurationPerMeasurement: Duration
    let maxEntriesPerScan: Int
    let maxBytesPerScan: Int64
    let maxDurationPerScan: Duration

    static let `default` = DirectorySizeLimits(
        maxEntriesPerMeasurement: 100_000,
        maxBytesPerMeasurement: 128 * 1_024 * 1_024 * 1_024,
        maxDurationPerMeasurement: .seconds(1),
        maxEntriesPerScan: 500_000,
        maxBytesPerScan: 512 * 1_024 * 1_024 * 1_024,
        maxDurationPerScan: .seconds(3)
    )
}

enum DirectorySizeIncompleteReason: Sendable, Equatable {
    case entryLimit
    case byteLimit
    case timeLimit
    case scanEntryLimit
    case scanByteLimit
    case scanTimeLimit
    case unreadable
    case unsafeRoot
}

enum DirectorySizeResult: Sendable, Equatable {
    case complete(Int64)
    case incomplete(DirectorySizeIncompleteReason)

    var sizeBytes: Int64? {
        guard case .complete(let size) = self else { return nil }
        return size
    }
}

enum SizeRoot: Sendable, Equatable {
    case tree(URL)
    case file(URL)

    fileprivate var url: URL {
        switch self {
        case .tree(let url), .file(let url): url
        }
    }
}

/// Measures logical bytes without following symlinks or publishing partial sums.
/// A fresh mutable value is created inside each scanner invocation so budget state
/// never crosses tasks or actor boundaries.
struct BoundedDirectorySizer {
    private struct PendingItem {
        let url: URL
        let rootKind: SizeRoot?
    }

    private let directoryAccess: any DirectoryAccessProvider
    private let limits: DirectorySizeLimits
    private let clock: ContinuousClock
    private let scanStartedAt: ContinuousClock.Instant
    private var scanEntries = 0
    private var scanBytes: Int64 = 0

    init(
        directoryAccess: any DirectoryAccessProvider,
        limits: DirectorySizeLimits = .default
    ) {
        self.directoryAccess = directoryAccess
        self.limits = limits
        let clock = ContinuousClock()
        self.clock = clock
        self.scanStartedAt = clock.now
    }

    mutating func measure(
        _ roots: [SizeRoot],
        constrainedTo allowedRoot: URL? = nil
    ) async throws -> DirectorySizeResult {
        try Task.checkCancellation()
        if let allowedRoot {
            let resolvedBoundary = directoryAccess
                .resolvingSymlinks(at: allowedRoot.standardizedFileURL)
                .standardizedFileURL
            for root in roots {
                try Task.checkCancellation()
                let resolvedRoot = directoryAccess
                    .resolvingSymlinks(at: root.url.standardizedFileURL)
                    .standardizedFileURL
                guard Self.isContained(resolvedRoot, in: resolvedBoundary) else {
                    return .incomplete(.unsafeRoot)
                }
            }
        }
        let measurementStartedAt = clock.now
        var measurementEntries = 0
        var measurementBytes: Int64 = 0
        var seenPaths: Set<String> = []
        var pending = roots
            .sorted { $0.url.standardizedFileURL.path > $1.url.standardizedFileURL.path }
            .map { PendingItem(url: $0.url, rootKind: $0) }

        while let item = pending.popLast() {
            if let reason = try await checkpoint(
                measurementStartedAt: measurementStartedAt,
                measurementEntries: measurementEntries
            ) {
                return .incomplete(reason)
            }

            let url = item.url.standardizedFileURL
            guard seenPaths.insert(url.path).inserted else { continue }

            measurementEntries += 1
            scanEntries += 1
            if measurementEntries > limits.maxEntriesPerMeasurement {
                return .incomplete(.entryLimit)
            }
            if scanEntries > limits.maxEntriesPerScan {
                return .incomplete(.scanEntryLimit)
            }

            let metadata: FileSystemItemMetadata
            do {
                metadata = try directoryAccess.metadata(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                if case .file = item.rootKind { continue }
                return .incomplete(.unreadable)
            } catch {
                return .incomplete(.unreadable)
            }

            if let reason = try await checkpoint(
                measurementStartedAt: measurementStartedAt,
                measurementEntries: measurementEntries
            ) {
                return .incomplete(reason)
            }

            switch metadata.kind {
            case .regularFile:
                if case .tree = item.rootKind {
                    return .incomplete(.unsafeRoot)
                }
                guard let size = metadata.logicalSizeBytes, size >= 0,
                      let nextMeasurement = addingWithoutOverflow(measurementBytes, size),
                      let nextScan = addingWithoutOverflow(scanBytes, size) else {
                    return .incomplete(.byteLimit)
                }
                if nextMeasurement > limits.maxBytesPerMeasurement {
                    return .incomplete(.byteLimit)
                }
                if nextScan > limits.maxBytesPerScan {
                    return .incomplete(.scanByteLimit)
                }
                measurementBytes = nextMeasurement
                scanBytes = nextScan

            case .directory:
                if case .file = item.rootKind {
                    return .incomplete(.unsafeRoot)
                }
                let children: [URL]
                do {
                    children = try directoryAccess.contentsOfDirectory(at: url)
                } catch {
                    return .incomplete(.unreadable)
                }
                if let reason = try await checkpoint(
                    measurementStartedAt: measurementStartedAt,
                    measurementEntries: measurementEntries
                ) {
                    return .incomplete(reason)
                }
                pending.append(contentsOf: children
                    .sorted { $0.standardizedFileURL.path > $1.standardizedFileURL.path }
                    .map { PendingItem(url: $0, rootKind: nil) })

            case .symbolicLink:
                if item.rootKind != nil {
                    return .incomplete(.unsafeRoot)
                }

            case .other:
                if item.rootKind != nil {
                    return .incomplete(.unsafeRoot)
                }
            }
        }

        return .complete(measurementBytes)
    }

    private func checkpoint(
        measurementStartedAt: ContinuousClock.Instant,
        measurementEntries: Int
    ) async throws -> DirectorySizeIncompleteReason? {
        try Task.checkCancellation()
        let now = clock.now
        if measurementStartedAt.duration(to: now) >= limits.maxDurationPerMeasurement {
            return .timeLimit
        }
        if scanStartedAt.duration(to: now) >= limits.maxDurationPerScan {
            return .scanTimeLimit
        }
        if measurementEntries.isMultiple(of: 32) {
            await Task.yield()
            try Task.checkCancellation()
        }
        return nil
    }

    private func addingWithoutOverflow(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : sum
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count >= rootComponents.count
            && candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }
}
