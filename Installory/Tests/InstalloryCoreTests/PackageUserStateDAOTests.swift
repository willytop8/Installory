import Testing
import Foundation
import GRDB
@testable import InstalloryCore

@Suite("PackageUserStateDAO")
struct PackageUserStateDAOTests {

    // MARK: - Helpers

    private func makeDatabase() throws -> (InstalloryCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageUserStateDAOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try InstalloryCore.Database(directory: dir), dir)
    }

    private func makeState(
        packageId: String = "brew::ffmpeg",
        isHidden: Bool = false,
        isPinned: Bool = false,
        note: String? = nil
    ) -> PackageUserState {
        PackageUserState(
            packageId: packageId,
            isHidden: isHidden,
            isPinned: isPinned,
            note: note,
            updatedAt: Date(timeIntervalSince1970: 1_723_000_000)
        )
    }

    // MARK: - Tests

    @Test("upsert then fetch returns the same state")
    func upsertAndFetch() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = PackageUserStateDAO(database: db)
        let state = makeState(packageId: "brew::ffmpeg", isHidden: true, isPinned: true, note: "core media")
        try await dao.upsert(state)

        let fetched = try await dao.fetch(packageId: "brew::ffmpeg")
        #expect(fetched?.packageId == "brew::ffmpeg")
        #expect(fetched?.isHidden == true)
        #expect(fetched?.isPinned == true)
        #expect(fetched?.note == "core media")
        #expect(fetched?.updatedAt == state.updatedAt)
    }

    @Test("upsert overwrites a previous row for the same package id")
    func upsertOverwritesPrevious() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = PackageUserStateDAO(database: db)
        try await dao.upsert(makeState(packageId: "brew::ffmpeg", isHidden: true, note: "first"))
        try await dao.upsert(
            PackageUserState(
                packageId: "brew::ffmpeg",
                isPinned: true,
                updatedAt: Date(timeIntervalSince1970: 1_723_100_000)
            )
        )

        let fetched = try await dao.fetch(packageId: "brew::ffmpeg")
        #expect(fetched?.isHidden == false)
        #expect(fetched?.isPinned == true)
        #expect(fetched?.note == nil)

        #expect(try await dao.fetchAll().count == 1)
    }

    @Test("upsertAll inserts multiple states and fetchAll returns them ordered")
    func upsertAllAndFetchAll() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = PackageUserStateDAO(database: db)
        try await dao.upsertAll([
            makeState(packageId: "brew::jq", note: "zebra"),
            makeState(packageId: "brew::ffmpeg", note: "alpha"),
            makeState(packageId: "brew::wget", note: "middle"),
        ])

        let all = try await dao.fetchAll()
        #expect(all.map(\.packageId) == ["brew::ffmpeg", "brew::jq", "brew::wget"])
        #expect(all.first { $0.packageId == "brew::jq" }?.note == "zebra")
    }

    @Test("delete removes one state; deleteAll removes every state")
    func deleteAndDeleteAll() async throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = PackageUserStateDAO(database: db)
        try await dao.upsertAll([
            makeState(packageId: "brew::ffmpeg"),
            makeState(packageId: "brew::jq"),
        ])

        try await dao.delete(packageId: "brew::ffmpeg")
        #expect(try await dao.fetch(packageId: "brew::ffmpeg") == nil)
        #expect(try await dao.fetchAll().count == 1)

        try await dao.deleteAll()
        #expect(try await dao.fetchAll().isEmpty)
    }

    @Test("GRDB record round-trip preserves note nil and booleans")
    func recordRoundTrip() throws {
        let (db, dir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        try db.pool.write { conn in
            try makeState(packageId: "brew::ffmpeg", isPinned: true).save(conn)
        }
        let fetched = try db.pool.read { conn in
            try PackageUserState.fetchOne(conn, key: "brew::ffmpeg")
        }
        #expect(fetched?.isPinned == true)
        #expect(fetched?.isHidden == false)
        #expect(fetched?.note == nil)
    }
}
