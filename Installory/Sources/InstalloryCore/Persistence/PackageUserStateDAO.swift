import Foundation
import GRDB

/// Reads and writes ``PackageUserState`` rows in the `package_user_state` table.
///
/// The table intentionally declares **no** foreign key to `packages`:
/// annotations like a note or pinned flag are meaningful even if the package
/// row is momentarily absent from the inventory (for example between an
/// uninstall and the next scan). Orphaned rows are harmless and are re-keyed
/// automatically when a matching package appears again.
public actor PackageUserStateDAO {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Inserts or updates the state for a package.
    ///
    /// Uses GRDB's `save` which updates if the `package_id` row exists,
    /// then inserts if no rows were changed.
    public func upsert(_ state: PackageUserState) throws {
        try upsertAll([state])
    }

    /// Inserts or updates a batch of state in one transaction.
    ///
    /// The operation is atomic: if any state fails to persist, none of the
    /// batch is committed. Input order is preserved, so when the batch repeats
    /// a package ID, the final occurrence supplies the stored values.
    public func upsertAll(_ states: [PackageUserState]) throws {
        try database.pool.write { db in
            for state in states {
                try state.save(db)
            }
        }
    }

    /// Returns the user state for `packageId`, or `nil` if none exists.
    public func fetch(packageId: String) throws -> PackageUserState? {
        try database.pool.read { db in
            try PackageUserState.fetchOne(db, key: packageId)
        }
    }

    /// Returns all persisted user state ordered by package ID.
    ///
    /// The explicit ordering keeps startup cache hydration and tests
    /// deterministic instead of depending on SQLite's table traversal order.
    public func fetchAll() throws -> [PackageUserState] {
        try database.pool.read { db in
            try PackageUserState.fetchAll(
                db,
                sql: "SELECT * FROM package_user_state ORDER BY package_id"
            )
        }
    }

    /// Removes the user state for `packageId`. No-op if no row exists.
    public func delete(packageId: String) throws {
        try database.pool.write { db in
            try db.execute(
                sql: "DELETE FROM package_user_state WHERE package_id = ?",
                arguments: [packageId]
            )
        }
    }

    /// Removes all rows from `package_user_state`.
    public func deleteAll() throws {
        try database.pool.write { db in
            try db.execute(sql: "DELETE FROM package_user_state")
        }
    }
}
