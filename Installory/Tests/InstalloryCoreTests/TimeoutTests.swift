import Testing
import Foundation
@testable import InstalloryCore

@Suite("withTimeout")
struct TimeoutTests {

    @Test("operation completing within timeout returns its value")
    func completesWithinTimeout() async throws {
        let result = try await withTimeout(5.0) { 42 }
        #expect(result == 42)
    }

    @Test("operation exceeding timeout throws TimeoutError")
    func exceedsTimeout() async throws {
        var threw = false
        do {
            _ = try await withTimeout(0.05) {
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms > 50ms timeout
                return 0
            }
        } catch is TimeoutError {
            threw = true
        }
        #expect(threw)
    }

    @Test("operation throwing its own error propagates that error, not TimeoutError")
    func propagatesOwnError() async throws {
        struct MyError: Error {}
        var threwMine = false
        do {
            let _: Int = try await withTimeout(5.0) { throw MyError() }
        } catch is MyError {
            threwMine = true
        } catch is TimeoutError {
            Issue.record("Expected MyError but got TimeoutError")
        }
        #expect(threwMine)
    }
}
