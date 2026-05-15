import Testing
import Foundation
import GRDB
@testable import CruftCore

@Suite("Database")
struct DatabaseTests {

    // MARK: - Helpers

    private func makeTempDatabase() throws -> (CruftCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CruftTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try CruftCore.Database(directory: dir)
        return (db, dir)
    }

    // MARK: - Schema

    @Test("Migrations create all four tables")
    func allTablesExist() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tables = try db.pool.read { conn -> [String] in
            try String.fetchAll(
                conn,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
        }
        #expect(tables.contains("packages"))
        #expect(tables.contains("provenance_evidence"))
        #expect(tables.contains("snapshots"))
        #expect(tables.contains("scan_runs"))
    }

    @Test("packages table has required columns")
    func packagesColumns() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rows = try db.pool.read { conn in
            try Row.fetchAll(conn, sql: "PRAGMA table_info(packages)")
        }
        let names = Set(rows.map { row -> String in row["name"] })
        let required: Set<String> = [
            "id", "manager", "qualifier", "name", "version",
            "install_path", "installed_at", "installed_at_confidence",
            "size_bytes", "is_explicit", "is_read_only", "dependencies",
            "artifact_paths", "last_seen",
        ]
        for col in required {
            #expect(names.contains(col), "packages must have column '\(col)'")
        }
    }

    @Test("provenance_evidence table has required columns")
    func provenanceColumns() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rows = try db.pool.read { conn in
            try Row.fetchAll(conn, sql: "PRAGMA table_info(provenance_evidence)")
        }
        let names = Set(rows.map { row -> String in row["name"] })
        #expect(names.contains("package_id"))
        #expect(names.contains("payload"))
        #expect(names.contains("collected_at"))
        #expect(names.contains("overall_confidence"))
    }

    @Test("snapshots table has required columns")
    func snapshotsColumns() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rows = try db.pool.read { conn in
            try Row.fetchAll(conn, sql: "PRAGMA table_info(snapshots)")
        }
        let names = Set(rows.map { row -> String in row["name"] })
        #expect(names.contains("id"))
        #expect(names.contains("created_at"))
        #expect(names.contains("reason"))
        #expect(names.contains("note"))
        #expect(names.contains("payload"))
    }

    @Test("scan_runs table has required columns")
    func scanRunsColumns() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rows = try db.pool.read { conn in
            try Row.fetchAll(conn, sql: "PRAGMA table_info(scan_runs)")
        }
        let names = Set(rows.map { row -> String in row["name"] })
        #expect(names.contains("id"))
        #expect(names.contains("started_at"))
        #expect(names.contains("completed_at"))
        #expect(names.contains("per_manager_results"))
    }

    // MARK: - Idempotency

    @Test("Running migrations twice is idempotent")
    func migrationsIdempotent() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Should not throw; DatabaseMigrator skips already-applied migrations.
        try Migrations.run(db.pool)

        let tables = try db.pool.read { conn -> [String] in
            try String.fetchAll(
                conn,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
        }
        #expect(tables.contains("packages"))
    }

    // MARK: - GRDB record round-trips

    @Test("Package inserts and fetches via GRDB")
    func packageGRDBRoundTrip() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = Package(
            id: "brew::git",
            manager: .brew,
            qualifier: nil,
            name: "git",
            version: "2.44.0",
            installPath: URL(fileURLWithPath: "/opt/homebrew/Cellar/git/2.44.0"),
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            installedAtConfidence: .high,
            sizeBytes: 50_000_000,
            isExplicit: true,
            isReadOnly: false,
            dependencies: ["gettext", "pcre2"],
            artifactPaths: nil,
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )

        try db.pool.write { conn in
            try original.insert(conn)
        }

        let fetched = try db.pool.read { conn in
            try Package.fetchOne(conn, key: "brew::git")
        }

        #expect(fetched != nil)
        #expect(fetched?.id == original.id)
        #expect(fetched?.manager == original.manager)
        #expect(fetched?.name == original.name)
        #expect(fetched?.dependencies == original.dependencies)
        #expect(fetched?.isExplicit == original.isExplicit)
        #expect(fetched?.isReadOnly == original.isReadOnly)
        #expect(fetched?.artifactPaths == nil)
    }

    @Test("Package artifact paths round-trip through GRDB")
    func packageArtifactPathsGRDBRoundTrip() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = Package(
            id: "brewCask::visual-studio-code",
            manager: .brewCask,
            qualifier: nil,
            name: "visual-studio-code",
            version: "1.90.2",
            installPath: URL(fileURLWithPath: "/opt/homebrew/Caskroom/visual-studio-code/1.90.2"),
            installedAt: Date(timeIntervalSince1970: 1_715_000_000),
            installedAtConfidence: .high,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            artifactPaths: ["Visual Studio Code.app", "~/Library/Application Support/Code", "~/.vscode"],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )

        try db.pool.write { conn in
            try original.insert(conn)
        }

        let fetched = try db.pool.read { conn in
            try Package.fetchOne(conn, key: "brewCask::visual-studio-code")
        }

        #expect(fetched?.artifactPaths == original.artifactPaths)
    }

    @Test("Package with nil optionals round-trips through GRDB")
    func packageNilFieldsGRDB() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = Package(
            id: "pip:/usr/bin/python3:six",
            manager: .pip,
            qualifier: "/usr/bin/python3",
            name: "six",
            version: "1.16.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .unknown,
            sizeBytes: nil,
            isExplicit: false,
            isReadOnly: true,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )

        try db.pool.write { conn in
            try original.insert(conn)
        }

        let fetched = try db.pool.read { conn in
            try Package.fetchOne(conn, key: "pip:/usr/bin/python3:six")
        }

        #expect(fetched?.installPath == nil)
        #expect(fetched?.installedAt == nil)
        #expect(fetched?.sizeBytes == nil)
        #expect(fetched?.isReadOnly == true)
    }

    // MARK: - GRDB round-trips: ProvenanceEvidence

    @Test("ProvenanceEvidence inserts and fetches via GRDB")
    func provenanceEvidenceGRDBRoundTrip() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        // ProvenanceEvidence has a FK to packages; insert the parent first.
        let pkg = Package(
            id: "brew::ffmpeg",
            manager: .brew,
            qualifier: nil,
            name: "ffmpeg",
            version: "6.1.1",
            installPath: nil,
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            installedAtConfidence: .high,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )
        try db.pool.write { conn in try pkg.insert(conn) }

        let original = ProvenanceEvidence(
            packageId: "brew::ffmpeg",
            fsInstallTime: Date(timeIntervalSince1970: 1_700_000_000),
            fsInstallTimeSource: "INSTALL_RECEIPT.json",
            installCommand: ProvenanceEvidence.InstallCommandRecord(
                timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                command: "brew install ffmpeg",
                shell: .zsh,
                cwd: "/Users/x/projects/video-tool"
            ),
            claudeCodeContext: nil,
            nearbyProjects: [
                ProvenanceEvidence.NearbyProject(
                    path: "/Users/x/projects/video-tool",
                    modifiedFileCount: 3,
                    gitCommitsThatDay: 1
                )
            ],
            coInstalledWithin1h: ["brew::x264"],
            overallConfidence: .high,
            collectedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )

        try db.pool.write { conn in try original.insert(conn) }

        let fetched = try db.pool.read { conn in
            try ProvenanceEvidence.fetchOne(conn, key: "brew::ffmpeg")
        }

        let f = try #require(fetched, "expected ProvenanceEvidence row to exist")
        #expect(f.packageId == original.packageId)
        #expect(f.overallConfidence == original.overallConfidence)
        #expect(f.fsInstallTimeSource == original.fsInstallTimeSource)
        #expect(f.installCommand?.command == original.installCommand?.command)
        #expect(f.installCommand?.shell == original.installCommand?.shell)
        #expect(f.nearbyProjects.count == 1)
        #expect(f.coInstalledWithin1h == ["brew::x264"])
        #expect(f.claudeCodeContext == nil)
    }

    @Test("ProvenanceEvidence with all-nil optionals round-trips via GRDB")
    func provenanceEvidenceNilSignalsGRDB() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pkg = Package(
            id: "cargo::ripgrep",
            manager: .cargo,
            qualifier: nil,
            name: "ripgrep",
            version: "14.1.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .unknown,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )
        try db.pool.write { conn in try pkg.insert(conn) }

        let original = ProvenanceEvidence(
            packageId: "cargo::ripgrep",
            fsInstallTime: nil,
            fsInstallTimeSource: nil,
            installCommand: nil,
            claudeCodeContext: nil,
            nearbyProjects: [],
            coInstalledWithin1h: [],
            overallConfidence: .unknown,
            collectedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )

        try db.pool.write { conn in try original.insert(conn) }

        let fetched = try db.pool.read { conn in
            try ProvenanceEvidence.fetchOne(conn, key: "cargo::ripgrep")
        }

        let f = try #require(fetched)
        #expect(f.fsInstallTime == nil)
        #expect(f.installCommand == nil)
        #expect(f.claudeCodeContext == nil)
        #expect(f.nearbyProjects.isEmpty)
        #expect(f.overallConfidence == .unknown)
    }

    // MARK: - GRDB round-trips: Snapshot

    @Test("Snapshot inserts and fetches via GRDB")
    func snapshotGRDBRoundTrip() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = Snapshot(
            id: UUID(uuidString: "aaaabbbb-cccc-dddd-eeee-ffffffffffff")!,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            reason: .manual,
            note: "pre-cleanup snapshot",
            payload: SnapshotPayload(managers: [
                .brew: [
                    SnapshotPackage(name: "git", version: "2.44.0", qualifier: nil, isExplicit: true),
                    SnapshotPackage(name: "openssl@3", version: "3.3.0", qualifier: nil, isExplicit: false),
                ],
                .pip: [
                    SnapshotPackage(
                        name: "requests",
                        version: "2.31.0",
                        qualifier: "/usr/bin/python3",
                        isExplicit: true
                    ),
                ],
            ])
        )

        try db.pool.write { conn in try original.insert(conn) }

        let fetched = try db.pool.read { conn in
            try Snapshot.fetchOne(conn, key: original.id.uuidString)
        }

        let f = try #require(fetched, "expected Snapshot row to exist")
        #expect(f.id == original.id)
        #expect(f.reason == original.reason)
        #expect(f.note == original.note)
        #expect(f.payload.managers[.brew]?.count == 2)
        #expect(f.payload.managers[.pip]?.count == 1)
        #expect(f.payload.managers[.pip]?.first?.qualifier == "/usr/bin/python3")
    }

    @Test("Snapshot with nil note round-trips via GRDB")
    func snapshotNilNoteGRDB() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = Snapshot(
            id: UUID(uuidString: "11112222-3333-4444-5555-666677778888")!,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            reason: .autoFirstScan,
            note: nil,
            payload: SnapshotPayload(managers: [:])
        )

        try db.pool.write { conn in try original.insert(conn) }

        let fetched = try db.pool.read { conn in
            try Snapshot.fetchOne(conn, key: original.id.uuidString)
        }

        let f = try #require(fetched)
        #expect(f.note == nil)
        #expect(f.reason == .autoFirstScan)
        #expect(f.payload.managers.isEmpty)
    }

    // MARK: - GRDB round-trips: ScanRun

    @Test("ScanRun inserts and fetches via GRDB")
    func scanRunGRDBRoundTrip() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = ScanRun(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            completedAt: Date(timeIntervalSince1970: 1_710_000_012),
            perManagerResults: [
                .brew: .succeeded(count: 247, durationMs: 1200),
                .pip: .succeeded(count: 89, durationMs: 800),
                .mas: .skipped(reason: "sandboxed: mas not supported"),
                .cargo: .failed(reason: "permission denied", durationMs: 99),
            ]
        )

        try db.pool.write { conn in try original.insert(conn) }

        let fetched = try db.pool.read { conn in
            try ScanRun.fetchOne(conn, key: original.id.uuidString)
        }

        let f = try #require(fetched, "expected ScanRun row to exist")
        #expect(f.id == original.id)
        #expect(f.completedAt != nil)
        #expect(f.perManagerResults[.brew] == .succeeded(count: 247, durationMs: 1200))
        #expect(f.perManagerResults[.pip] == .succeeded(count: 89, durationMs: 800))
        #expect(f.perManagerResults[.mas] == .skipped(reason: "sandboxed: mas not supported"))
        #expect(f.perManagerResults[.cargo] == .failed(reason: "permission denied", durationMs: 99))
    }

    @Test("ScanRun with nil completedAt round-trips via GRDB")
    func scanRunNilCompletedAtGRDB() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = ScanRun(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            completedAt: nil,
            perManagerResults: [.npm: .timedOut(durationMs: 15_000)]
        )

        try db.pool.write { conn in try original.insert(conn) }

        let fetched = try db.pool.read { conn in
            try ScanRun.fetchOne(conn, key: original.id.uuidString)
        }

        let f = try #require(fetched)
        #expect(f.completedAt == nil)
        #expect(f.perManagerResults[.npm] == .timedOut(durationMs: 15_000))
    }
}
