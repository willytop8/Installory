import Testing
import Foundation
import GRDB
@testable import InstalloryCore

@Suite("ProvenanceDAO")
struct ProvenanceDAOTests {

    // MARK: - Helpers

    private func makeDatabase() throws -> (InstalloryCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProvenanceDAOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try InstalloryCore.Database(directory: dir), dir)
    }

    /// Inserts a minimal packages row so the FK constraint on provenance_evidence is satisfied.
    private func seedPackage(db: InstalloryCore.Database, id: String) throws {
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

    private func makeUpdatedEvidence(
        packageId: String = "brew::ffmpeg",
        secret: String? = nil
    ) -> ProvenanceEvidence {
        ProvenanceEvidence(
            packageId: packageId,
            fsInstallTime: Date(timeIntervalSince1970: 1_723_000_000),
            fsInstallTimeSource: "INSTALL_RECEIPT.json",
            installCommand: ProvenanceEvidence.InstallCommandRecord(
                timestamp: nil,
                command: secret.map { "PASSWORD=\($0) brew install ffmpeg" }
                    ?? "brew install ffmpeg",
                shell: .zsh,
                cwd: nil
            ),
            claudeCodeContext: nil,
            nearbyProjects: [],
            coInstalledWithin1h: ["brew::libpng"],
            overallConfidence: .medium,
            collectedAt: Date(timeIntervalSince1970: 1_723_200_000)
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

        let updated = makeUpdatedEvidence()
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

    @Test("upsertAll inserts and updates a batch with the last duplicate winning")
    func upsertAllInsertsAndUpdates() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        for id in ["brew::ffmpeg", "brew::wget", "brew::jq"] {
            try seedPackage(db: db, id: id)
        }
        let dao = ProvenanceDAO(database: db)
        try await dao.upsert(makeEvidence(packageId: "brew::ffmpeg"))
        try await dao.upsert(makeEvidence(packageId: "brew::jq"))

        try await dao.upsertAll([
            makeUpdatedEvidence(packageId: "brew::ffmpeg"),
            makeEvidence(packageId: "brew::wget"),
            makeUpdatedEvidence(packageId: "brew::wget"),
        ])

        let evidence = try await dao.fetchAll()
        #expect(evidence.map(\.packageId) == ["brew::ffmpeg", "brew::jq", "brew::wget"])
        #expect(evidence.first { $0.packageId == "brew::ffmpeg" }?.overallConfidence == .medium)
        #expect(evidence.first { $0.packageId == "brew::jq" }?.overallConfidence == .low)
        #expect(evidence.first { $0.packageId == "brew::wget" }?.overallConfidence == .medium)
    }

    @Test("upsertAll rolls back the entire batch on a foreign-key failure")
    func upsertAllRollsBackAtomically() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try seedPackage(db: db, id: "brew::ffmpeg")
        let dao = ProvenanceDAO(database: db)
        try await dao.upsert(makeEvidence())

        await #expect(throws: (any Error).self) {
            try await dao.upsertAll([
                makeUpdatedEvidence(),
                makeEvidence(packageId: "brew::missing-package"),
            ])
        }

        let evidence = try await dao.fetchAll()
        #expect(evidence.count == 1)
        #expect(evidence.first?.packageId == "brew::ffmpeg")
        #expect(evidence.first?.overallConfidence == .low)
        #expect(evidence.first?.installCommand == nil)
    }

    @Test("fetchAll returns every row ordered by package ID")
    func fetchAllReturnsDeterministicBulkRead() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        for id in ["npm::typescript", "brew::ffmpeg", "cargo::ripgrep"] {
            try seedPackage(db: db, id: id)
        }
        let dao = ProvenanceDAO(database: db)
        try await dao.upsertAll([
            makeEvidence(packageId: "npm::typescript"),
            makeEvidence(packageId: "brew::ffmpeg"),
            makeEvidence(packageId: "cargo::ripgrep"),
        ])

        let evidence = try await dao.fetchAll()
        #expect(evidence.map(\.packageId) == [
            "brew::ffmpeg",
            "cargo::ripgrep",
            "npm::typescript",
        ])
    }

    @Test("upsertAll with empty input leaves existing evidence unchanged")
    func upsertAllEmptyInputIsNoOp() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try seedPackage(db: db, id: "brew::ffmpeg")
        let dao = ProvenanceDAO(database: db)
        try await dao.upsert(makeEvidence())

        try await dao.upsertAll([])

        let evidence = try await dao.fetchAll()
        #expect(evidence.count == 1)
        #expect(evidence.first?.packageId == "brew::ffmpeg")
        #expect(evidence.first?.overallConfidence == .low)
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

    @Test("persistence boundary redacts secrets before writing payload")
    func persistenceRedactsSecrets() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try seedPackage(db: db, id: "brew::ffmpeg")
        let raw = ProvenanceEvidence(
            packageId: "brew::ffmpeg",
            fsInstallTime: nil,
            fsInstallTimeSource: nil,
            installCommand: ProvenanceEvidence.InstallCommandRecord(
                timestamp: nil,
                command: "PASSWORD=database-secret brew install ffmpeg",
                shell: .zsh,
                cwd: nil
            ),
            claudeCodeContext: nil,
            nearbyProjects: [],
            coInstalledWithin1h: [],
            overallConfidence: .medium,
            collectedAt: .now
        )

        let dao = ProvenanceDAO(database: db)
        try await dao.upsert(raw)

        let payload = try await db.pool.read { conn in
            try String.fetchOne(
                conn,
                sql: "SELECT payload FROM provenance_evidence WHERE package_id = ?",
                arguments: ["brew::ffmpeg"]
            )
        }
        let stored = try #require(payload)
        #expect(!stored.contains("database-secret"))
        #expect(stored.contains("[REDACTED]"))

        let fetched = try #require(try await dao.fetch(packageId: "brew::ffmpeg"))
        #expect(fetched.installCommand?.command == "PASSWORD=[REDACTED] brew install ffmpeg")
    }

    @Test("upsertAll applies the persistence redaction boundary to every row")
    func upsertAllRedactsSecrets() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try seedPackage(db: db, id: "brew::ffmpeg")
        try seedPackage(db: db, id: "brew::wget")
        let dao = ProvenanceDAO(database: db)

        try await dao.upsertAll([
            makeUpdatedEvidence(packageId: "brew::ffmpeg", secret: "first-secret"),
            makeUpdatedEvidence(packageId: "brew::wget", secret: "second-secret"),
        ])

        let payloads = try await db.pool.read { conn in
            try String.fetchAll(
                conn,
                sql: "SELECT payload FROM provenance_evidence ORDER BY package_id"
            )
        }
        #expect(payloads.count == 2)
        #expect(payloads.allSatisfy { $0.contains("[REDACTED]") })
        #expect(payloads.allSatisfy { !$0.contains("first-secret") })
        #expect(payloads.allSatisfy { !$0.contains("second-secret") })

        let evidence = try await dao.fetchAll()
        #expect(evidence.allSatisfy {
            $0.installCommand?.command == "PASSWORD=[REDACTED] brew install ffmpeg"
        })
    }
}
