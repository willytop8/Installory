import Foundation
import GRDB

/// Captures, lists, retrieves, and deletes snapshots in the `snapshots` table.
public actor SnapshotManager {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Groups `packages` by manager into a `SnapshotPayload`, persists the snapshot,
    /// and returns it.
    public func capture(
        packages: [Package],
        reason: SnapshotReason,
        note: String?
    ) throws -> Snapshot {
        var grouped: [PackageManager: [SnapshotPackage]] = [:]
        for pkg in packages {
            grouped[pkg.manager, default: []].append(
                SnapshotPackage(
                    name: pkg.name,
                    version: pkg.version,
                    qualifier: pkg.qualifier,
                    isExplicit: pkg.isExplicit
                )
            )
        }
        let snapshot = Snapshot(
            id: UUID(),
            createdAt: Date(),
            reason: reason,
            note: note,
            payload: SnapshotPayload(managers: grouped)
        )
        try database.pool.write { db in
            try snapshot.insert(db)
        }
        return snapshot
    }

    /// Returns all snapshots ordered newest-first.
    public func list() throws -> [Snapshot] {
        try database.pool.read { db in
            try Snapshot.order(Column("created_at").desc).fetchAll(db)
        }
    }

    /// Returns the snapshot with the given id, or nil if it doesn't exist.
    public func snapshot(id: UUID) throws -> Snapshot? {
        try database.pool.read { db in
            try Snapshot.fetchOne(db, key: id.uuidString)
        }
    }

    /// Deletes the snapshot with the given id.
    public func delete(id: UUID) throws {
        try database.pool.write { db in
            try db.execute(
                sql: "DELETE FROM snapshots WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }
}
