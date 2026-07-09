import Foundation
import GRDB

/// Reads and writes ``Package`` rows in the `packages` table.
///
/// `Package` already conforms to `FetchableRecord` and `PersistableRecord`; this
/// DAO is a thin coordination layer that exposes a GRDB-free API to the app layer.
///
/// **Provenance cascade:** `replaceAll(with:)` deletes only the package rows that
/// have disappeared from the inventory, so `provenance_evidence`'s `ON DELETE
/// CASCADE` fires only for genuinely removed packages. Evidence for surviving
/// packages is preserved across rescans.
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

    /// Replaces the contents of the `packages` table with `packages` in a single transaction.
    ///
    /// The replacement is atomic: either all rows are replaced or none are.
    ///
    /// Rows are reconciled rather than wiped: ids absent from `packages` are deleted,
    /// and the rest are upserted in place. This matters because `provenance_evidence`
    /// cascades on package deletion, and provenance collection is expensive and opt-in —
    /// a blanket `DELETE FROM packages` would discard evidence for unchanged packages
    /// on every rescan.
    ///
    /// `upsert` is deliberate: `INSERT OR REPLACE` resolves a conflict by *deleting*
    /// the existing row, which fires the same cascade this method exists to avoid.
    public func replaceAll(with packages: [Package]) throws {
        try database.pool.write { db in
            let incomingIDs = Set(packages.map(\.id))
            let existingIDs = try String.fetchSet(db, sql: "SELECT id FROM packages")
            try Package.deleteAll(db, keys: existingIDs.subtracting(incomingIDs))
            for pkg in packages {
                try pkg.upsert(db)
            }
        }
    }
}
