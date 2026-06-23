import Foundation

/// Events emitted by `ScanCoordinator.scan()`.
public enum ScanEvent: Sendable {
    case scannerStarted(PackageManager)
    case scannerFinished(PackageManager, ScannerStatus, [Package])
    case allFinished(perManager: [PackageManager: ScannerStatus], allPackages: [Package])
}

/// Runs all registered `PackageScanner`s concurrently and streams `ScanEvent`s
/// as each scanner starts, finishes, and when all are done.
///
/// This is a pure actor — no `@Observable`, no `@MainActor`. A future
/// `@MainActor @Observable` view-model layer (Phase 5) will subscribe to the
/// event stream and project state into SwiftUI.
public actor ScanCoordinator {
    private let scanners: [any PackageScanner]
    private let timeouts: [PackageManager: TimeInterval]

    // npm is given the highest budget because deep nvm trees with many node
    // versions each carrying a large global node_modules can take noticeably
    // longer than the other scanners' filesystem walks.
    private static let defaultTimeouts: [PackageManager: TimeInterval] = [
        .brew: 5, .brewCask: 5, .pip: 8, .npm: 30,
        .pipx: 5, .cargo: 5, .gem: 5, .mas: 5,
    ]

    public init(
        scanners: [any PackageScanner],
        timeouts: [PackageManager: TimeInterval] = [:]
    ) {
        self.scanners = scanners
        self.timeouts = Self.defaultTimeouts.merging(timeouts) { _, override in override }
    }

    /// Runs every scanner concurrently and yields events as they happen.
    /// The stream completes after `.allFinished` is yielded.
    public func scan() -> AsyncStream<ScanEvent> {
        let scanners = self.scanners
        let timeouts = self.timeouts
        return AsyncStream { (continuation: AsyncStream<ScanEvent>.Continuation) in
            Task.detached {
                var allPackages: [Package] = []
                var perManager: [PackageManager: ScannerStatus] = [:]

                await withTaskGroup(of: (PackageManager, ScannerStatus, [Package]).self) { group in
                    for scanner in scanners {
                        let mgr = scanner.manager
                        let timeoutSecs = timeouts[mgr] ?? 30

                        group.addTask {
                            // .scannerStarted must be yielded before awaiting scan().
                            continuation.yield(.scannerStarted(mgr))
                            let start = Date()
                            let status: ScannerStatus
                            let packages: [Package]
                            do {
                                let pkgs = try await withTimeout(timeoutSecs) {
                                    guard await scanner.isAvailable() else {
                                        throw ScannerUnavailable(reason: scanner.unavailableReason)
                                    }
                                    return try await scanner.scan()
                                }
                                let ms = Int(Date().timeIntervalSince(start) * 1000)
                                status = .succeeded(count: pkgs.count, durationMs: ms)
                                packages = pkgs
                            } catch let unavailable as ScannerUnavailable {
                                status = .skipped(reason: unavailable.reason)
                                packages = []
                            } catch is TimeoutError {
                                let ms = Int(Date().timeIntervalSince(start) * 1000)
                                status = .timedOut(durationMs: ms)
                                packages = []
                            } catch {
                                let ms = Int(Date().timeIntervalSince(start) * 1000)
                                status = .failed(reason: error.localizedDescription, durationMs: ms)
                                packages = []
                            }
                            continuation.yield(.scannerFinished(mgr, status, packages))
                            return (mgr, status, packages)
                        }
                    }

                    for await (mgr, status, pkgs) in group {
                        perManager[mgr] = status
                        allPackages += pkgs
                    }
                }

                continuation.yield(.allFinished(perManager: perManager, allPackages: allPackages))
                continuation.finish()
            }
        }
    }
}

private struct ScannerUnavailable: Error, Sendable {
    let reason: String
}
