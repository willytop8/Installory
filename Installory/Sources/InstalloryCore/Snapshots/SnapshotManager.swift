import Foundation
import GRDB

/// Lightweight metadata used when listing snapshot history.
///
/// Snapshot payloads can contain thousands of packages, so list views should
/// retain summaries and load one full ``Snapshot`` only when it is selected.
public struct SnapshotSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let reason: SnapshotReason
    public let note: String?

    public init(
        id: UUID,
        createdAt: Date,
        reason: SnapshotReason,
        note: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        self.note = note
    }

    public init(snapshot: Snapshot) {
        self.init(
            id: snapshot.id,
            createdAt: snapshot.createdAt,
            reason: snapshot.reason,
            note: snapshot.note
        )
    }

    fileprivate init(row: Row) throws {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError(message: "snapshots.id '\(idString)' is not a valid UUID")
        }

        let reasonString: String = row["reason"]
        guard let reason = SnapshotReason(rawValue: reasonString) else {
            throw DatabaseError(message: "Unknown SnapshotReason '\(reasonString)' in snapshots row")
        }

        self.init(
            id: id,
            createdAt: Date(timeIntervalSince1970: row["created_at"] as Double),
            reason: reason,
            note: row["note"]
        )
    }
}

/// Captures, lists, retrieves, and deletes snapshots in the `snapshots` table.
public actor SnapshotManager {
    private let database: Database
    private let now: @Sendable () -> Date

    public init(
        database: Database,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.now = now
    }

    /// Groups `packages` by manager into a `SnapshotPayload`, persists the snapshot,
    /// and returns it.
    public func capture(
        packages: [Package],
        reason: SnapshotReason,
        note: String?
    ) async throws -> Snapshot {
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
            createdAt: now(),
            reason: reason,
            note: note,
            payload: SnapshotPayload(managers: grouped)
        )
        try await database.pool.write { db in
            try snapshot.insert(db)
        }
        return snapshot
    }

    /// Returns metadata for all snapshots ordered newest-first.
    ///
    /// The explicit projection is intentional: selecting `payload` here would
    /// make opening the sidebar decode and retain every historical inventory.
    public func list() async throws -> [SnapshotSummary] {
        try await database.pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, created_at, reason, note
                    FROM snapshots
                    ORDER BY created_at DESC, id ASC
                    """
            ).map(SnapshotSummary.init(row:))
        }
    }

    /// Returns the snapshot with the given id, or nil if it doesn't exist.
    public func snapshot(id: UUID) async throws -> Snapshot? {
        try await database.pool.read { db in
            try Snapshot.fetchOne(db, key: id.uuidString)
        }
    }

    /// Deletes the snapshot with the given id.
    public func delete(id: UUID) async throws {
        try await database.pool.write { db in
            try db.execute(
                sql: "DELETE FROM snapshots WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }
}
