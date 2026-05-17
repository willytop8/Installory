import Foundation
import GRDB

/// Reads and writes ``ScanRun`` rows in the `scan_runs` table.
///
/// `ScanRun` already conforms to `FetchableRecord` and `PersistableRecord`; this
/// DAO is a thin coordination layer that exposes a GRDB-free API to the app layer.
///
/// Scan runs accumulate over time and are not pruned automatically. They serve as a
/// diagnostic log; disk impact is negligible (<1 KB per row).
public struct ScanRunDAO: Sendable {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Persists `scanRun` to the `scan_runs` table.
    public func save(_ scanRun: ScanRun) throws {
        try database.pool.write { db in
            try scanRun.insert(db)
        }
    }

    /// Returns the `completedAt` timestamp of the most recent scan run, or `nil`
    /// if no scan runs have been recorded or the most recent run has no completion time.
    public func mostRecentCompletedAt() throws -> Date? {
        try database.pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT completed_at FROM scan_runs ORDER BY started_at DESC LIMIT 1"
            )
            guard let row = rows.first,
                  let ts: Double = row["completed_at"]
            else { return nil }
            return Date(timeIntervalSince1970: ts)
        }
    }
}
