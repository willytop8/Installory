import Foundation
import GRDB

/// Reads and writes ``Package`` rows in the `packages` table.
///
/// `Package` already conforms to `FetchableRecord` and `PersistableRecord`; this
/// DAO is a thin coordination layer that exposes a GRDB-free API to the app layer.
///
/// **Provenance cascade:** `replaceAll(with:)` deletes all package rows first.
/// Because `provenance_evidence` has `ON DELETE CASCADE`, this also removes all
/// evidence rows. Phase 5c does not collect provenance at scan time; this is acceptable.
public struct PackageDAO: Sendable {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Returns all persisted packages, in the order they appear in the table.
    public func loadAll() throws -> [Package] {
        try database.pool.read { db in
            try Package.fetchAll(db)
        }
    }

    /// Replaces every row in the `packages` table with `packages` in a single transaction.
    ///
    /// The replacement is atomic: either all rows are replaced or none are.
    public func replaceAll(with packages: [Package]) throws {
        try database.pool.write { db in
            try db.execute(sql: "DELETE FROM packages")
            for pkg in packages {
                try pkg.insert(db)
            }
        }
    }
}
