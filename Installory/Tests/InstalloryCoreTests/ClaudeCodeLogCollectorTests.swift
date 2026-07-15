import Testing
import Foundation
@testable import InstalloryCore

@Suite("ClaudeCodeLogCollector")
struct ClaudeCodeLogCollectorTests {
    private let home = URL(fileURLWithPath: "/fake-home")
    private let podcastDir = URL(fileURLWithPath: "/fake-home/.claude/projects/-Users-will-projects-podcast-app")
    private let myAppDir   = URL(fileURLWithPath: "/fake-home/.claude/projects/-Users-will-projects-my-app")

    private func fixtureData(_ relativePath: String) throws -> Data {
        try FixtureResource.data("claude-code/\(relativePath)")
    }

    private func makeProvider() throws -> InMemoryDirectoryAccessProvider {
        let sessionIndex = try fixtureData(
            "projects/-Users-will-projects-podcast-app/sessions-index.json"
        )
        let firstPodcastSession = try fixtureData(
            "projects/-Users-will-projects-podcast-app/abc-111-uuid.jsonl"
        )
        let secondPodcastSession = try fixtureData(
            "projects/-Users-will-projects-podcast-app/def-222-uuid.jsonl"
        )
        let myAppSession = try fixtureData(
            "projects/-Users-will-projects-my-app/ghi-333-uuid.jsonl"
        )

        return InMemoryDirectoryAccessProvider.make { builder in
            // podcast-app: sessions-index.json + two session files
            builder.addFile(
                at: podcastDir.appendingPathComponent("sessions-index.json"),
                data: sessionIndex
            )
            builder.addFile(
                at: podcastDir.appendingPathComponent("abc-111-uuid.jsonl"),
                data: firstPodcastSession
            )
            builder.addFile(
                at: podcastDir.appendingPathComponent("def-222-uuid.jsonl"),
                data: secondPodcastSession
            )
            // my-app: no sessions-index.json; directory name is ambiguous (-Users-will-projects-my-app)
            builder.addFile(
                at: myAppDir.appendingPathComponent("ghi-333-uuid.jsonl"),
                data: myAppSession
            )
        }
    }

    // MARK: - Count

    @Test("detects install commands across all project directories")
    func totalCount() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.count == 3)
    }

    // MARK: - projectPath

    @Test("cwd field overrides dashed-directory-name path reconstruction")
    func cwdOverridesPathReconstruction() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        let ts = records.first { $0.packageName == "typescript" }
        // Naive reconstruction: -Users-will-projects-my-app → /Users/will/projects/my/app (wrong)
        // cwd in JSONL: /Users/will/projects/my-app (correct)
        #expect(ts?.context.projectPath == "/Users/will/projects/my-app")
    }

    @Test("podcast-app projectPath comes from cwd field")
    func podcastProjectPath() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        let whisper = records.first { $0.packageName == "openai-whisper" }
        #expect(whisper?.context.projectPath == "/Users/will/projects/podcast-app")
    }

    // MARK: - sessionId

    @Test("sessionId is taken from the JSONL sessionId field")
    func sessionIdFromField() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        let whisper = records.first { $0.packageName == "openai-whisper" }
        #expect(whisper?.context.sessionId == "abc-111-uuid")
    }

    // MARK: - timestamp

    @Test("timestamp is parsed from the JSONL timestamp field")
    func timestampParsed() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        let whisper = records.first { $0.packageName == "openai-whisper" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = formatter.date(from: "2025-08-14T15:23:00.000Z")
        #expect(whisper?.context.timestamp == expected)
    }

    // MARK: - firstUserMessage

    @Test("firstUserMessage is the chronologically first user message in the session")
    func firstUserMessage() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        let whisper = records.first { $0.packageName == "openai-whisper" }
        #expect(whisper?.context.firstUserMessage == "help me build a podcast transcription script")
    }

    @Test("firstUserMessage is first-by-timestamp even when events appear out of file order")
    func firstUserMessageByTimestamp() {
        // The later-timestamped user message appears first in the file.
        // The collector must select the earlier-timestamped one.
        let laterLine = #"{"sessionId":"ord-test","timestamp":"2025-01-01T12:00:00.000Z","cwd":"/tmp","message":{"role":"user","content":[{"type":"text","text":"second message (later)"}]}}"#
        let earlierLine = #"{"sessionId":"ord-test","timestamp":"2025-01-01T11:00:00.000Z","cwd":"/tmp","message":{"role":"user","content":[{"type":"text","text":"first message (earlier)"}]}}"#
        let installLine = #"{"sessionId":"ord-test","timestamp":"2025-01-01T12:01:00.000Z","cwd":"/tmp","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"brew install wget"}}]}}"#
        let jsonl = [laterLine, earlierLine, installLine].joined(separator: "\n")

        let sessionDir = URL(fileURLWithPath: "/fake-home/.claude/projects/-tmp")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: sessionDir.appendingPathComponent("ord-test.jsonl"),
                data: Data(jsonl.utf8)
            )
        }
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.count == 1)
        #expect(records.first?.context.firstUserMessage == "first message (earlier)")
    }

    // MARK: - sessionSummary

    @Test("sessionSummary populated when sessions-index.json has matching entry")
    func sessionSummaryPresent() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        let whisper = records.first { $0.packageName == "openai-whisper" }
        #expect(whisper?.context.sessionSummary == "Built a podcast transcription script using Whisper")
    }

    @Test("sessionSummary is nil when no sessions-index.json exists for the project")
    func sessionSummaryAbsent() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        let ts = records.first { $0.packageName == "typescript" }
        #expect(ts?.context.sessionSummary == nil)
    }

    // MARK: - bashInvocation

    @Test("bashInvocation is the raw command string from input.command")
    func bashInvocation() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        let whisper = records.first { $0.packageName == "openai-whisper" }
        #expect(whisper?.context.bashInvocation == "pip install openai-whisper")
    }

    // MARK: - Filtering

    @Test("non-install Bash commands produce no results")
    func nonInstallBashFiltered() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        // abc-111-uuid.jsonl has `ls -la` — should not appear in results
        #expect(!records.contains { $0.context.bashInvocation == "ls -la" })
    }

    @Test("non-Bash tool_use blocks (e.g. Read) produce no results")
    func nonBashToolUseFiltered() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        // Exactly 3 installs — no extra record from the Read tool_use in abc-111-uuid.jsonl
        #expect(records.count == 3)
    }

    // MARK: - Resilience

    @Test("malformed JSONL line is skipped; remaining lines in the file still produce results")
    func malformedLineSkipped() throws {
        let provider = try makeProvider()
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        // abc-111-uuid.jsonl has one invalid-JSON line; openai-whisper install still detected
        #expect(records.contains { $0.packageName == "openai-whisper" })
    }

    @Test("CORE25-013: invalid UTF-8 discards only its Claude JSONL line")
    func invalidUTF8DiscardsOnlyCorruptLine() {
        let userLine = #"{"sessionId":"utf8-test","timestamp":"2025-01-01T11:00:00.000Z","cwd":"/tmp","message":{"role":"user","content":"install my tools"}}"#
        let installLine = #"{"sessionId":"utf8-test","timestamp":"2025-01-01T11:01:00.000Z","cwd":"/tmp","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"brew install wget"}}]}}"#
        var jsonl = Data(userLine.utf8)
        jsonl.append(contentsOf: [0x0A, 0xFF, 0x0A])
        jsonl.append(Data(installLine.utf8))

        let sessionDir = URL(fileURLWithPath: "/fake-home/.claude/projects/-tmp")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: sessionDir.appendingPathComponent("utf8-test.jsonl"),
                data: jsonl
            )
        }

        let records = ClaudeCodeLogCollector(
            directoryAccess: provider,
            homeDirectory: home
        ).collect()

        #expect(records.count == 1)
        #expect(records.first?.packageName == "wget")
        #expect(records.first?.context.firstUserMessage == "install my tools")
    }

    @Test("PERF25-005: oversized session is rejected before loading its bytes")
    func oversizedSessionIsNotLoaded() {
        let sessionDir = URL(fileURLWithPath: "/fake-home/.claude/projects/-tmp")
        let sessionURL = sessionDir.appendingPathComponent("oversized.jsonl")
        let base = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: sessionURL,
                data: Data("{}\n".utf8),
                logicalSizeBytes: 100 * 1_024 * 1_024
            )
        }
        let trace = DirectoryAccessTrace()
        let provider = TracingDirectoryAccessProvider(base: base, trace: trace)

        let records = ClaudeCodeLogCollector(
            directoryAccess: provider,
            homeDirectory: home
        ).collect()

        #expect(records.isEmpty)
        #expect(trace.entries.contains { $0.operation == .metadata && $0.url == sessionURL })
        #expect(!trace.entries.contains { $0.operation == .data && $0.url == sessionURL })
    }

    @Test("missing ~/.claude/projects yields empty result without crashing")
    func missingProjectsDirectory() {
        let provider = InMemoryDirectoryAccessProvider.make { _ in }
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.isEmpty)
    }

    @Test("project directory with no .jsonl files yields no results for that project")
    func emptyProjectDirectory() {
        // Register only a sessions-index.json (no JSONL files) under a project dir.
        let emptyDir = URL(fileURLWithPath: "/fake-home/.claude/projects/-Users-will-projects-empty")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: emptyDir.appendingPathComponent("sessions-index.json"),
                data: Data(#"{"sessions":[]}"#.utf8)
            )
        }
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.isEmpty)
    }

    @Test("malformed sessions-index.json does not crash; summaries treated as nil")
    func malformedSessionsIndex() {
        let dir = URL(fileURLWithPath: "/fake-home/.claude/projects/-tmp-project")
        let installLine = #"{"sessionId":"s1","timestamp":"2025-01-01T10:00:00.000Z","cwd":"/tmp","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"gem install jekyll"}}]}}"#
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: dir.appendingPathComponent("sessions-index.json"),
                data: Data("NOT JSON".utf8)
            )
            builder.addFile(
                at: dir.appendingPathComponent("s1.jsonl"),
                data: Data(installLine.utf8)
            )
        }
        let records = ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.count == 1)
        #expect(records.first?.packageName == "jekyll")
        #expect(records.first?.context.sessionSummary == nil)
    }
}
