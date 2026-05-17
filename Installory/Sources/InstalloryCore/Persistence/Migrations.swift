import GRDB

/// Append-only migration definitions for the Installory SQLite database.
///
/// **Never modify a registered migration after it has been shipped.**
/// Add a new `registerMigration` call for every schema change.
/// `DatabaseMigrator` guarantees each migration runs exactly once.
public enum Migrations {

    /// Applies all pending migrations to `writer`.
    ///
    /// Safe to call multiple times — already-applied migrations are skipped.
    public static func run(_ writer: some DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial", migrate: v1Initial)
        migrator.registerMigration("v2_package_artifact_paths", migrate: v2PackageArtifactPaths)
        try migrator.migrate(writer)
    }

    // MARK: - Migration bodies

    private static func v1Initial(_ db: GRDB.Database) throws {
        // packages — current inventory
        try db.execute(sql: """
            CREATE TABLE packages (
                id                      TEXT PRIMARY KEY,
                manager                 TEXT NOT NULL,
                qualifier               TEXT,
                name                    TEXT NOT NULL,
                version                 TEXT NOT NULL,
                install_path            TEXT,
                installed_at            REAL,
                installed_at_confidence TEXT NOT NULL,
                size_bytes              INTEGER,
                is_explicit             INTEGER NOT NULL DEFAULT 0,
                is_read_only            INTEGER NOT NULL DEFAULT 0,
                dependencies            TEXT NOT NULL DEFAULT '[]',
                last_seen               REAL NOT NULL
            )
            """)
        try db.execute(sql: "CREATE INDEX idx_packages_manager ON packages(manager)")
        try db.execute(sql: "CREATE INDEX idx_packages_name ON packages(name)")

        // provenance_evidence — structured signals, stored as JSON payload
        // collected_at and overall_confidence are extracted as indexed columns
        // so queries can filter by confidence without deserializing the blob.
        try db.execute(sql: """
            CREATE TABLE provenance_evidence (
                package_id         TEXT PRIMARY KEY,
                payload            TEXT NOT NULL,
                collected_at       REAL NOT NULL,
                overall_confidence TEXT NOT NULL,
                FOREIGN KEY (package_id) REFERENCES packages(id) ON DELETE CASCADE
            )
            """)

        // snapshots — point-in-time export manifests
        try db.execute(sql: """
            CREATE TABLE snapshots (
                id         TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                reason     TEXT NOT NULL,
                note       TEXT,
                payload    TEXT NOT NULL
            )
            """)
        try db.execute(sql: "CREATE INDEX idx_snapshots_created ON snapshots(created_at DESC)")

        // scan_runs — diagnostic log of scanner invocations
        try db.execute(sql: """
            CREATE TABLE scan_runs (
                id                  TEXT PRIMARY KEY,
                started_at          REAL NOT NULL,
                completed_at        REAL,
                per_manager_results TEXT NOT NULL
            )
            """)
    }

    private static func v2PackageArtifactPaths(_ db: GRDB.Database) throws {
        try db.execute(sql: "ALTER TABLE packages ADD COLUMN artifact_paths TEXT")
    }
}
