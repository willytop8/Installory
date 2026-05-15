import Foundation
import GRDB

/// Reads and writes ``ProvenanceEvidence`` rows in the `provenance_evidence` table.
///
/// **FK prerequisite:** `provenance_evidence.package_id` has a
/// `FOREIGN KEY … REFERENCES packages(id)` constraint. Call ``upsert(_:)`` only
/// after the corresponding ``Package`` row has been persisted. Phase 5's app shell
/// sequences this correctly: scan → persist packages → collect provenance →
/// persist evidence. The FK violation is the runtime signal for a mis-sequenced call.
public actor ProvenanceDAO {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Inserts or updates the evidence for a package.
    ///
    /// Uses GRDB's `save` which updates if the `package_id` row exists,
    /// then inserts if no rows were changed.
    ///
    /// - Precondition: the `packages` row for `evidence.packageId` must exist.
    public func upsert(_ evidence: ProvenanceEvidence) throws {
        try database.pool.write { db in
            try evidence.save(db)
        }
    }

    /// Returns the evidence for `packageId`, or `nil` if no row exists.
    public func fetch(packageId: String) throws -> ProvenanceEvidence? {
        try database.pool.read { db in
            try ProvenanceEvidence.fetchOne(db, key: packageId)
        }
    }

    /// Removes the evidence for `packageId`. No-op if no row exists.
    public func delete(packageId: String) throws {
        try database.pool.write { db in
            try db.execute(
                sql: "DELETE FROM provenance_evidence WHERE package_id = ?",
                arguments: [packageId]
            )
        }
    }

    /// Removes all rows from `provenance_evidence`.
    public func deleteAll() throws {
        try database.pool.write { db in
            try db.execute(sql: "DELETE FROM provenance_evidence")
        }
    }
}
