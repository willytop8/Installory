import Testing
import Foundation
import GRDB
@testable import BackshelfCore

@Suite("SnapshotManager")
struct SnapshotManagerTests {

    // MARK: - Helpers

    private func makeDatabase() throws -> (BackshelfCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try BackshelfCore.Database(directory: dir), dir)
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

        let manager = SnapshotManager(database: db)

        let first = try await manager.capture(
            packages: [makePackage("git")],
            reason: .manual,
            note: "first"
        )
        // Small sleep to guarantee distinct createdAt timestamps.
        try await Task.sleep(nanoseconds: 10_000_000)
        let second = try await manager.capture(
            packages: [makePackage("wget")],
            reason: .manual,
            note: "second"
        )

        let list = try await manager.list()

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

        let row = try db.pool.read { conn in
            try Row.fetchOne(
                conn,
                sql: "SELECT * FROM snapshots WHERE id = ?",
                arguments: [snapshot.id.uuidString]
            )
        }

        let r = try #require(row)
        let idInRow: String = r["id"]
        let reasonInRow: String = r["reason"]
        #expect(idInRow == snapshot.id.uuidString)
        #expect(reasonInRow == "manual")
    }
}
