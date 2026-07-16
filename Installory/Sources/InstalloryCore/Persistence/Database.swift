import Foundation
import GRDB

/// The Installory writable SQLite database.
///
/// Wraps a GRDB `DatabasePool` and runs migrations on initialization.
/// Consumers interact with the database through `pool` directly using
/// GRDB's read/write APIs.
///
/// The caller supplies an existing directory. The app uses its sandboxed
/// Application Support directory; external scan grants are unrelated to the
/// writable local cache.
public final class Database: Sendable {

    /// The underlying connection pool. Use for all reads and writes.
    public let pool: DatabasePool

    /// Opens (or creates) `installory.db` inside `directory` and applies migrations.
    ///
    /// - Parameter directory: The directory that will contain `installory.db`.
    ///   The directory must already exist; this initializer does not create it.
    /// - Throws: A GRDB `DatabaseError` if the pool cannot be opened, or a
    ///   migration error if the schema cannot be applied.
    public init(directory: URL) throws {
        let dbURL = directory.appendingPathComponent("installory.db")
        pool = try DatabasePool(path: dbURL.path)
        try Migrations.run(pool)
    }
}
