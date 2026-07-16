import Testing
import Foundation
import GRDB
@testable import InstalloryCore

@Suite("SnapshotManager")
struct SnapshotManagerTests {

    // MARK: - Helpers

    private func makeDatabase() throws -> (InstalloryCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try InstalloryCore.Database(directory: dir), dir)
    }

    private func makePackage(_ name: String, manager: PackageManager = .brew) -> Package {
        Package(
            id: "\(manager.rawValue)::\(name)",
            manager: manager,
            qualifier: nil,
            name: name,
            version: "1.0.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .unknown,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    // MARK: - Tests

    @Test("capture returns snapshot and list finds it")
    func captureAndList() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = SnapshotManager(database: db)
        let snapshot = try await manager.capture(
            packages: [makePackage("git"), makePackage("wget")],
            reason: .manual,
            note: "test snapshot"
        )
        let list = try await manager.list()

        #expect(list.count == 1)
        #expect(list[0].id == snapshot.id)
        #expect(list[0].note == "test snapshot")
        #expect(list[0].reason == .manual)
    }

    @Test("list is ordered newest-first")
    func listNewestFirst() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let firstManager = SnapshotManager(
            database: db,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let secondManager = SnapshotManager(
            database: db,
            now: { Date(timeIntervalSince1970: 200) }
        )

        let first = try await firstManager.capture(
            packages: [makePackage("git")],
            reason: .manual,
            note: "first"
        )
        let second = try await secondManager.capture(
            packages: [makePackage("wget")],
            reason: .manual,
            note: "second"
        )

        let list = try await secondManager.list()

        #expect(list.count == 2)
        #expect(list[0].id == second.id)
        #expect(list[1].id == first.id)
    }

    @Test("snapshot(id:) round-trips fields including payload manager groupings")
    func snapshotRoundTrip() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = SnapshotManager(database: db)
        let captured = try await manager.capture(
            packages: [
                makePackage("git", manager: .brew),
                makePackage("wget", manager: .brew),
                makePackage("requests", manager: .pip),
            ],
            reason: .preUninstall,
            note: nil
        )

        let fetched = try await manager.snapshot(id: captured.id)

        let s = try #require(fetched)
        #expect(s.id == captured.id)
        #expect(s.reason == .preUninstall)
        #expect(s.note == nil)
        #expect(s.payload.managers[.brew]?.count == 2)
        #expect(s.payload.managers[.pip]?.count == 1)
    }

    @Test("PERF25-008: listing skips large payloads and targeted loading decodes only one row")
    func listUsesMetadataAndTargetedLoadDoesNotDecodeOtherPayloads() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = SnapshotManager(database: db)
        let packageCount = 5_000
        let largeSnapshot = try await manager.capture(
            packages: (0..<packageCount).map { makePackage("package-\($0)") },
            reason: .manual,
            note: "large valid payload"
        )

        // This row is deliberately large and impossible to decode as a
        // SnapshotPayload. A metadata list must still succeed, and loading the
        // valid row must not scan/decode this unrelated payload first.
        let poisonedID = UUID()
        let malformedLargePayload = "{\"brew\":[" + String(repeating: "x", count: 1_000_000)
        try await db.pool.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO snapshots (id, created_at, reason, note, payload)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    poisonedID.uuidString,
                    largeSnapshot.createdAt.addingTimeInterval(1).timeIntervalSince1970,
                    SnapshotReason.preCleanup.rawValue,
                    "malformed large payload",
                    malformedLargePayload,
                ]
            )
        }

        let summaries = try await manager.list()
        #expect(summaries.map(\.id) == [poisonedID, largeSnapshot.id])
        #expect(summaries[0].note == "malformed large payload")
        #expect(summaries[1].note == "large valid payload")

        let loaded = try #require(try await manager.snapshot(id: largeSnapshot.id))
        #expect(loaded.payload.managers[.brew]?.count == packageCount)
    }

    @Test("delete removes snapshot from list")
    func deleteRemoves() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = SnapshotManager(database: db)
        let snapshot = try await manager.capture(
            packages: [makePackage("git")],
            reason: .manual,
            note: nil
        )

        try await manager.delete(id: snapshot.id)
        let list = try await manager.list()

        #expect(list.isEmpty)
    }

    @Test("capture with empty packages array creates empty payload")
    func captureEmpty() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = SnapshotManager(database: db)
        let snapshot = try await manager.capture(packages: [], reason: .autoFirstScan, note: nil)

        #expect(snapshot.payload.managers.isEmpty)
        let list = try await manager.list()
        #expect(list.count == 1)
    }

    @Test("capture persists to the snapshots GRDB table")
    func captureWritesToGRDB() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = SnapshotManager(database: db)
        let snapshot = try await manager.capture(
            packages: [makePackage("git")],
            reason: .manual,
            note: nil
        )

        let persistedValues = try await db.pool.read { conn -> (id: String, reason: String)? in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT * FROM snapshots WHERE id = ?",
                arguments: [snapshot.id.uuidString]
            ) else {
                return nil
            }
            return (row["id"], row["reason"])
        }

        let values = try #require(persistedValues)
        #expect(values.id == snapshot.id.uuidString)
        #expect(values.reason == "manual")
    }
}
