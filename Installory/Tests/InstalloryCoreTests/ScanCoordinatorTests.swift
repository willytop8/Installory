import Testing
import Foundation
@testable import InstalloryCore

// MARK: - MockScanner

private struct MockScanner: PackageScanner, Sendable {
    let manager: PackageManager
    private let behavior: @Sendable () async throws -> [Package]

    init(manager: PackageManager, _ behavior: @escaping @Sendable () async throws -> [Package]) {
        self.manager = manager
        self.behavior = behavior
    }

    func isAvailable() async -> Bool { true }
    func scan() async throws -> [Package] { try await behavior() }

    static func succeeding(manager: PackageManager, packages: [Package] = []) -> MockScanner {
        MockScanner(manager: manager) { packages }
    }

    static func throwing(manager: PackageManager, error: some Error & Sendable) -> MockScanner {
        MockScanner(manager: manager) { throw error }
    }

    static func delaying(manager: PackageManager, seconds: TimeInterval) -> MockScanner {
        MockScanner(manager: manager) {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return []
        }
    }
}

// MARK: - Helpers

private func collectEvents(from coordinator: ScanCoordinator) async -> [ScanEvent] {
    var events: [ScanEvent] = []
    for await event in await coordinator.scan() {
        events.append(event)
    }
    return events
}

private func makePackage(_ name: String, manager: PackageManager) -> Package {
    Package(
        id: "\(manager.rawValue)::\(name)",
        manager: manager,
        qualifier: nil,
        name: name,
        version: "1.0.0",
        installPath: nil,
        installedAt: nil,
        installedAtConfidence: .unknown,
        sizeBytes: nil,
        isExplicit: true,
        isReadOnly: false,
        dependencies: [],
        lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
    )
}

// MARK: - Tests

@Suite("ScanCoordinator")
struct ScanCoordinatorTests {

    @Test("all scanners succeed: allFinished aggregates all packages and succeeded statuses")
    func allSucceed() async throws {
        let pkgA = makePackage("git", manager: .brew)
        let pkgB = makePackage("typescript", manager: .npm)
        let coordinator = ScanCoordinator(
            scanners: [
                MockScanner.succeeding(manager: .brew, packages: [pkgA]),
                MockScanner.succeeding(manager: .npm, packages: [pkgB]),
            ],
            timeouts: [.brew: 5, .npm: 5]
        )

        let events = await collectEvents(from: coordinator)

        guard case .allFinished(let perManager, let allPackages) = events.last else {
            Issue.record("last event must be .allFinished, got \(String(describing: events.last))")
            return
        }
        #expect(allPackages.count == 2)
        #expect(perManager.count == 2)

        guard case .succeeded(let brewCount, _) = perManager[.brew] else {
            Issue.record(".brew status must be .succeeded")
            return
        }
        #expect(brewCount == 1)

        guard case .succeeded(let npmCount, _) = perManager[.npm] else {
            Issue.record(".npm status must be .succeeded")
            return
        }
        #expect(npmCount == 1)
    }

    @Test("one scanner throws: that manager gets .failed status, others still complete")
    func oneThrows() async throws {
        struct ScanError: Error, Sendable {}
        let coordinator = ScanCoordinator(
            scanners: [
                MockScanner.throwing(manager: .brew, error: ScanError()),
                MockScanner.succeeding(manager: .npm),
            ],
            timeouts: [.brew: 5, .npm: 5]
        )

        let events = await collectEvents(from: coordinator)

        guard case .allFinished(let perManager, _) = events.last else {
            Issue.record("last event must be .allFinished")
            return
        }
        guard case .failed(_, _) = perManager[.brew] else {
            Issue.record(".brew must have .failed status, got \(String(describing: perManager[.brew]))")
            return
        }
        guard case .succeeded(0, _) = perManager[.npm] else {
            Issue.record(".npm must have .succeeded(0, _) status")
            return
        }
    }

    @Test("one scanner exceeds timeout: that manager gets .timedOut status, others still complete")
    func oneTimesOut() async throws {
        let coordinator = ScanCoordinator(
            scanners: [
                MockScanner.delaying(manager: .brew, seconds: 2), // far exceeds 0.05s timeout
                MockScanner.succeeding(manager: .npm),
            ],
            timeouts: [.brew: 0.05, .npm: 5]
        )

        let events = await collectEvents(from: coordinator)

        guard case .allFinished(let perManager, _) = events.last else {
            Issue.record("last event must be .allFinished")
            return
        }
        guard case .timedOut(_) = perManager[.brew] else {
            Issue.record(".brew must have .timedOut status, got \(String(describing: perManager[.brew]))")
            return
        }
        guard case .succeeded(0, _) = perManager[.npm] else {
            Issue.record(".npm must have .succeeded(0, _) status")
            return
        }
    }

    @Test("empty scanner list: scan emits only allFinished with empty state")
    func emptyScannerList() async throws {
        let coordinator = ScanCoordinator(scanners: [])
        let events = await collectEvents(from: coordinator)

        #expect(events.count == 1)
        guard case .allFinished(let perManager, let allPackages) = events[0] else {
            Issue.record("only event must be .allFinished")
            return
        }
        #expect(perManager.isEmpty)
        #expect(allPackages.isEmpty)
    }

    @Test("scannerStarted always precedes the matching scannerFinished for each manager")
    func startedBeforeFinished() async throws {
        let coordinator = ScanCoordinator(
            scanners: [
                MockScanner.succeeding(manager: .brew),
                MockScanner.succeeding(manager: .npm),
            ],
            timeouts: [.brew: 5, .npm: 5]
        )

        let events = await collectEvents(from: coordinator)

        for mgr in [PackageManager.brew, .npm] {
            let startedIdx = events.firstIndex {
                if case .scannerStarted(let m) = $0 { return m == mgr }
                return false
            }
            let finishedIdx = events.firstIndex {
                if case .scannerFinished(let m, _, _) = $0 { return m == mgr }
                return false
            }
            let si = try #require(startedIdx, "\(mgr): missing .scannerStarted")
            let fi = try #require(finishedIdx, "\(mgr): missing .scannerFinished")
            #expect(si < fi, "\(mgr): .scannerStarted index \(si) must be before .scannerFinished index \(fi)")
        }
    }

    @Test("durationMs is non-negative for all scanners regardless of outcome")
    func durationNonNegative() async throws {
        struct ScanError: Error, Sendable {}
        let coordinator = ScanCoordinator(
            scanners: [
                MockScanner.succeeding(manager: .brew),
                MockScanner.throwing(manager: .npm, error: ScanError()),
                MockScanner.delaying(manager: .cargo, seconds: 2),
            ],
            timeouts: [.brew: 5, .npm: 5, .cargo: 0.05]
        )

        let events = await collectEvents(from: coordinator)

        for event in events {
            if case .scannerFinished(_, let status, _) = event {
                switch status {
                case .succeeded(_, let ms): #expect(ms >= 0)
                case .failed(_, let ms): #expect(ms >= 0)
                case .timedOut(let ms): #expect(ms >= 0)
                case .skipped: break
                }
            }
        }
    }
}
