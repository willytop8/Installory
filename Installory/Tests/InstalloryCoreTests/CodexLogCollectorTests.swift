import Testing
import Foundation
@testable import InstalloryCore

@Suite("CodexLogCollector")
struct CodexLogCollectorTests {
    private let home = URL(fileURLWithPath: "/fake-home")
    private let sessionFile = URL(
        fileURLWithPath: "/fake-home/.codex/sessions/2026/03/01/"
            + "rollout-2026-03-01T00-18-27-019ca80c-5804-7491-834e-237de100eb49.jsonl"
    )

    private func makeProvider(session jsonl: String) -> InMemoryDirectoryAccessProvider {
        InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: sessionFile, data: Data(jsonl.utf8))
        }
    }

    private func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    // MARK: - Parsing

    @Test("reads an exec_command install with session_meta context")
    func readsExecCommandInstall() {
        let jsonl = """
            {"timestamp":"2026-03-01T06:18:30.087Z","type":"session_meta","payload":{"id":"019ca80c-5804-7491-834e-237de100eb49","cwd":"/Users/will/projects/tooling"}}
            {"timestamp":"2026-03-01T06:19:00.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"brew install wget\\"}"}}
            """
        let records = CodexLogCollector(
            directoryAccess: makeProvider(session: jsonl),
            homeDirectory: home
        ).collect()
        #expect(records.count == 1)
        let record = records[0]
        #expect(record.packageName == "wget")
        #expect(record.manager == .brew)
        #expect(record.context.bashInvocation == "brew install wget")
        #expect(record.context.sessionId == "019ca80c-5804-7491-834e-237de100eb49")
        #expect(record.context.projectPath == "/Users/will/projects/tooling")
        #expect(record.context.sessionSummary == nil)
        #expect(record.context.firstUserMessage == nil)
    }

    @Test("timestamp is parsed from the top-level ISO8601 field")
    func timestampParsed() {
        let jsonl = """
            {"timestamp":"2026-03-01T06:18:30.087Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp"}}
            {"timestamp":"2026-03-01T06:19:15.500Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"brew install wget\\"}"}}
            """
        let records = CodexLogCollector(
            directoryAccess: makeProvider(session: jsonl),
            homeDirectory: home
        ).collect()
        #expect(records.first?.context.timestamp == formatter().date(from: "2026-03-01T06:19:15.500Z"))
    }

    @Test("session id falls back to the rollout filename when no session_meta exists")
    func sessionIdFallsBackToFilename() {
        let jsonl = """
            {"timestamp":"2026-03-01T06:19:00.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"brew install wget\\"}"}}
            """
        let records = CodexLogCollector(
            directoryAccess: makeProvider(session: jsonl),
            homeDirectory: home
        ).collect()
        #expect(records.first?.context.sessionId == "019ca80c-5804-7491-834e-237de100eb49")
        #expect(records.first?.context.projectPath == "")
    }

    // MARK: - Filtering

    @Test("non-exec_command payloads produce no results")
    func nonExecCommandIgnored() {
        let jsonl = """
            {"timestamp":"2026-03-01T06:18:30.087Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp"}}
            {"timestamp":"2026-03-01T06:19:00.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ok"}]}}
            {"timestamp":"2026-03-01T06:19:05.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_shim","arguments":"{\\"cmd\\":\\"brew install wget\\"}"}}
            """
        let records = CodexLogCollector(
            directoryAccess: makeProvider(session: jsonl),
            homeDirectory: home
        ).collect()
        #expect(records.isEmpty)
    }

    @Test("non-install exec_command commands produce no results")
    func nonInstallCommandIgnored() {
        let jsonl = """
            {"timestamp":"2026-03-01T06:18:30.087Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp"}}
            {"timestamp":"2026-03-01T06:19:00.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"ls -la\\"}"}}
            """
        let records = CodexLogCollector(
            directoryAccess: makeProvider(session: jsonl),
            homeDirectory: home
        ).collect()
        #expect(records.isEmpty)
    }

    @Test("a single exec_command installing several packages yields one record per package")
    func multipleDetectionsPerCommand() {
        let jsonl = """
            {"timestamp":"2026-03-01T06:18:30.087Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp"}}
            {"timestamp":"2026-03-01T06:19:00.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"brew install wget curl\\"}"}}
            """
        let records = CodexLogCollector(
            directoryAccess: makeProvider(session: jsonl),
            homeDirectory: home
        ).collect()
        #expect(records.count == 2)
        #expect(Set(records.map(\.packageName)) == ["wget", "curl"])
        // Both records share one session context.
        #expect(records[0].context.sessionId == records[1].context.sessionId)
    }

    @Test("malformed JSONL line is skipped; remaining lines still produce results")
    func malformedLineSkipped() {
        let jsonl = """
            {"timestamp":"2026-03-01T06:18:30.087Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp"}}
            NOT JSON
            {"timestamp":"2026-03-01T06:19:00.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"brew install wget\\"}"}}
            """
        let records = CodexLogCollector(
            directoryAccess: makeProvider(session: jsonl),
            homeDirectory: home
        ).collect()
        #expect(records.count == 1)
        #expect(records.first?.packageName == "wget")
    }

    // MARK: - Resilience

    @Test("missing ~/.codex/sessions yields empty result without crashing")
    func missingSessionsDirectory() {
        let provider = InMemoryDirectoryAccessProvider.make { _ in }
        let records = CodexLogCollector(
            directoryAccess: provider,
            homeDirectory: home
        ).collect()
        #expect(records.isEmpty)
    }

    @Test("non-numeric date directories are ignored")
    func nonNumericDateDirsIgnored() {
        let stray = URL(fileURLWithPath: "/fake-home/.codex/sessions/README.md")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: stray, data: Data("not a dir".utf8))
            builder.addFile(at: sessionFile, data: Data("""
                {"timestamp":"2026-03-01T06:18:30.087Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp"}}
                {"timestamp":"2026-03-01T06:19:00.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"brew install wget\\"}"}}
                """.utf8))
        }
        let records = CodexLogCollector(
            directoryAccess: provider,
            homeDirectory: home
        ).collect()
        #expect(records.count == 1)
        #expect(records.first?.packageName == "wget")
    }
}
