import Testing
import Foundation
import GRDB
@testable import BackshelfCore

@Suite("ProvenanceDAO")
struct ProvenanceDAOTests {

    // MARK: - Helpers

    private func makeDatabase() throws -> (BackshelfCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProvenanceDAOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try BackshelfCore.Database(directory: dir), dir)
    }

    /// Inserts a minimal packages row so the FK constraint on provenance_evidence is satisfied.
    private func seedPackage(db: BackshelfCore.Database, id: String) throws {
        let parts = id.split(separator: "::", maxSplits: 1)
        let manager = parts.first.map(String.init) ?? "brew"
        let name = parts.last.map(String.init) ?? id
        try db.pool.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO packages
                        (id, manager, name, version, installed_at_confidence, last_seen)
                    VALUES (?, ?, ?, '1.0', 'unknown', 0)
                    """,
                arguments: [id, manager, name]
            )
        }
    }

    private func makeEvidence(packageId: String = "brew::ffmpeg") -> ProvenanceEvidence {
        ProvenanceEvidence(
            packageId: packageId,
            fsInstallTime: Date(timeIntervalSince1970: 1_723_000_000),
            fsInstallTimeSource: "INSTALL_RECEIPT.json",
            installCommand: nil,
            claudeCodeContext: nil,
            nearbyProjects: [],
            coInstalledWithin1h: [],
            overallConfidence: .low,
            collectedAt: Date(timeIntervalSince1970: 1_723_100_000)
        )
    }

    // MARK: - Tests

    @Test("upsert then fetch returns the same evidence")
    func upsertAndFetch() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try seedPackage(db: db, id: "brew::ffmpeg")
        let dao = ProvenanceDAO(database: db)
        let original = makeEvidence()
        try await dao.upsert(original)

        let fetched = try await dao.fetch(packageId: original.packageId)
        let e = try #require(fetched)
        #expect(e.packageId == original.packageId)
        #expect(e.overallConfidence == original.overallConfidence)
        #expect(e.fsInstallTimeSource == original.fsInstallTimeSource)
        #expect(e.coInstalledWithin1h == original.coInstalledWithin1h)
    }

    @Test("upsert twice with same packageId keeps only the latest values")
    func upsertOverwritesPrevious() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try seedPackage(db: db, id: "brew::ffmpeg")
        let dao = ProvenanceDAO(database: db)
        try await dao.upsert(makeEvidence())

        let updated = ProvenanceEvidence(
            packageId: "brew::ffmpeg",
            fsInstallTime: Date(timeIntervalSince1970: 1_723_000_000),
            fsInstallTimeSource: "INSTALL_RECEIPT.json",
            installCommand: ProvenanceEvidence.InstallCommandRecord(
                timestamp: nil,
                command: "brew install ffmpeg",
                shell: .zsh,
                cwd: nil
            ),
            claudeCodeContext: nil,
            nearbyProjects: [],
            coInstalledWithin1h: ["brew::libpng"],
            overallConfidence: .medium,
            collectedAt: Date(timeIntervalSince1970: 1_723_200_000)
        )
        try await dao.upsert(updated)

        let fetched = try await dao.fetch(packageId: "brew::ffmpeg")
        let e = try #require(fetched)
        #expect(e.overallConfidence == .medium)
        #expect(e.coInstalledWithin1h == ["brew::libpng"])
        #expect(e.installCommand?.command == "brew install ffmpeg")

        // Confirm only one row exists, not two.
        let count = try await db.pool.read { conn in
            try Int.fetchOne(
                conn,
                sql: "SELECT COUNT(*) FROM provenance_evidence WHERE package_id = ?",
                arguments: ["brew::ffmpeg"]
            ) ?? 0
        }
        #expect(count == 1)
    }

    @Test("delete removes the evidence for the given packageId")
    func deleteRemovesEvidence() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try seedPackage(db: db, id: "brew::ffmpeg")
        let dao = ProvenanceDAO(database: db)
        try await dao.upsert(makeEvidence())
        try await dao.delete(packageId: "brew::ffmpeg")

        let fetched = try await dao.fetch(packageId: "brew::ffmpeg")
        #expect(fetched == nil)
    }

    @Test("deleteAll empties the provenance_evidence table")
    func deleteAllEmptiesTable() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try seedPackage(db: db, id: "brew::ffmpeg")
        try seedPackage(db: db, id: "brew::wget")
        let dao = ProvenanceDAO(database: db)
        try await dao.upsert(makeEvidence(packageId: "brew::ffmpeg"))
        try await dao.upsert(makeEvidence(packageId: "brew::wget"))
        try await dao.deleteAll()

        let count = try await db.pool.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM provenance_evidence") ?? 0
        }
        #expect(count == 0)
    }

    @Test("fetch of a nonexistent packageId returns nil")
    func fetchNonexistentReturnsNil() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = ProvenanceDAO(database: db)
        let result = try await dao.fetch(packageId: "brew::does-not-exist")
        #expect(result == nil)
    }
}
