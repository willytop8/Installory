import Testing
import Foundation
import GRDB
@testable import InstalloryCore

@Suite("OpenCodeLogCollector")
struct OpenCodeLogCollectorTests {
    /// Builds a minimal opencode.db on disk: only the `session` and `part`
    /// tables the collector reads.
    private func makeDB(rows: [(sessionID: String, directory: String, title: String, ms: Int64, data: String)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("opencode.db")
        let queue = try DatabaseQueue(path: dbURL.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT NOT NULL, title TEXT NOT NULL)")
            try db.execute(sql: """
                CREATE TABLE part (
                    id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    time_created INTEGER NOT NULL,
                    time_updated INTEGER NOT NULL,
                    data TEXT NOT NULL
                )
                """)
            for (index, row) in rows.enumerated() {
                if index == 0 || rows[index - 1].sessionID != row.sessionID {
                    try db.execute(
                        sql: "INSERT INTO session (id, directory, title) VALUES (?, ?, ?)",
                        arguments: [row.sessionID, row.directory, row.title]
                    )
                }
                try db.execute(
                    sql: "INSERT INTO part (id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?)",
                    arguments: ["p\(index)", row.sessionID, row.ms, row.ms, row.data]
                )
            }
        }
        return dbURL
    }

    private let sampleMilliseconds: Int64 = 1_771_624_907_295

    // MARK: - Parsing

    @Test("reads a bash install command with session context")
    func readsBashInstallCommand() throws {
        let dbURL = try makeDB(rows: [
            (
                sessionID: "sess-123",
                directory: "/Users/will/projects/tooling",
                title: "Add wget to the toolchain",
                ms: sampleMilliseconds,
                data: #"{"type":"tool","tool":"bash","state":{"input":{"command":"brew install wget","description":"Install wget"}}}"#
            ),
        ])
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let records = OpenCodeLogCollector(databasePath: dbURL).collect()
        #expect(records.count == 1)
        let record = records[0]
        #expect(record.packageName == "wget")
        #expect(record.manager == .brew)
        #expect(record.context.bashInvocation == "brew install wget")
        #expect(record.context.sessionId == "sess-123")
        #expect(record.context.projectPath == "/Users/will/projects/tooling")
        #expect(record.context.sessionSummary == "Add wget to the toolchain")
        #expect(record.context.firstUserMessage == nil)
    }

    @Test("timestamp is converted from unix milliseconds")
    func timestampConvertedFromMilliseconds() throws {
        let dbURL = try makeDB(rows: [
            (
                sessionID: "sess-1",
                directory: "/tmp/project",
                title: "t",
                ms: sampleMilliseconds,
                data: #"{"type":"tool","tool":"bash","state":{"input":{"command":"brew install wget"}}}"#
            ),
        ])
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let records = OpenCodeLogCollector(databasePath: dbURL).collect()
        #expect(records.first?.context.timestamp == Date(timeIntervalSince1970: 1_771_624_907.295))
    }

    // MARK: - Filtering

    @Test("ignores non-bash tool parts")
    func ignoresNonBashTools() throws {
        let dbURL = try makeDB(rows: [
            (
                sessionID: "sess-1",
                directory: "/tmp/project",
                title: "t",
                ms: sampleMilliseconds,
                data: #"{"type":"tool","tool":"websearch","state":{"input":{"query":"brew install wget"}}}"#
            ),
        ])
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let records = OpenCodeLogCollector(databasePath: dbURL).collect()
        #expect(records.isEmpty)
    }

    @Test("ignores non-install commands")
    func ignoresNonInstallCommands() throws {
        let dbURL = try makeDB(rows: [
            (
                sessionID: "sess-1",
                directory: "/tmp/project",
                title: "t",
                ms: sampleMilliseconds,
                data: #"{"type":"tool","tool":"bash","state":{"input":{"command":"npm run lint"}}}"#
            ),
        ])
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let records = OpenCodeLogCollector(databasePath: dbURL).collect()
        #expect(records.isEmpty)
    }

    @Test("skips malformed data JSON rows")
    func malformedDataJSONIsSkipped() throws {
        let dbURL = try makeDB(rows: [
            (
                sessionID: "sess-1",
                directory: "/tmp/project",
                title: "t",
                ms: sampleMilliseconds,
                data: "this is not json"
            ),
            (
                sessionID: "sess-1",
                directory: "/tmp/project",
                title: "t",
                ms: sampleMilliseconds + 1,
                data: #"{"type":"tool","tool":"bash","state":{"input":{"command":"brew install wget"}}}"#
            ),
        ])
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let records = OpenCodeLogCollector(databasePath: dbURL).collect()
        #expect(records.count == 1)
        #expect(records.first?.packageName == "wget")
    }

    // MARK: - Resilience

    @Test("missing database file yields empty result without crashing")
    func missingDatabaseFileIsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        let records = OpenCodeLogCollector(databasePath: missing).collect()
        #expect(records.isEmpty)
    }
}
