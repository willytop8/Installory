import Foundation
import GRDB

/// The Cruft writable SQLite database.
///
/// Wraps a GRDB `DatabasePool` and runs migrations on initialization.
/// Consumers interact with the database through `pool` directly using
/// GRDB's read/write APIs.
///
/// **Phase 0 limitation:** The caller supplies a `directory` URL directly.
/// In the shipping app this URL will arrive from `FolderAccessManager` as
/// a security-scoped bookmark resolved to the app's Application Support
/// container. See HANDOFF.md for the full handoff note.
public final class Database: Sendable {

    /// The underlying connection pool. Use for all reads and writes.
    public let pool: DatabasePool

    /// Opens (or creates) `cruft.db` inside `directory` and applies migrations.
    ///
    /// - Parameter directory: The directory that will contain `cruft.db`.
    ///   The directory must already exist; this initializer does not create it.
    /// - Throws: A GRDB `DatabaseError` if the pool cannot be opened, or a
    ///   migration error if the schema cannot be applied.
    public init(directory: URL) throws {
        let dbURL = directory.appendingPathComponent("cruft.db")
        pool = try DatabasePool(path: dbURL.path)
        try Migrations.run(pool)
    }
}
