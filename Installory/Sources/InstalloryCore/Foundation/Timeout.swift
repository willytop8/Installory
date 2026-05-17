import Foundation

public struct TimeoutError: Error, Sendable {}

/// Runs `operation`, throwing `TimeoutError` if it doesn't complete within `seconds`.
///
/// Uses a two-task group: one for the operation, one as a timer. Whichever
/// finishes first wins; the other is cancelled. The drain loop after
/// `cancelAll()` prevents the cancelled task's `CancellationError` from
/// propagating via `withThrowingTaskGroup`'s implicit final-drain.
public func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        // Consume the cancelled task so the group is empty on body exit.
        // CancellationError from the cancelled peer is expected and discarded.
        do { while try await group.next() != nil {} } catch {}
        return result
    }
}
