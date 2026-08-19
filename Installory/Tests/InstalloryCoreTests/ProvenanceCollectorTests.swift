import Testing
import Foundation
import GRDB
@testable import InstalloryCore

@Suite("ProvenanceCollector")
struct ProvenanceCollectorTests {

    // Baseline timestamp used across tests. All offsets are relative to this.
    private let t0 = Date(timeIntervalSince1970: 1_723_000_000)
    private let home = URL(fileURLWithPath: "/fake-home")

    // MARK: - Helpers

    private func makePackage(
        _ name: String,
        manager: PackageManager = .brew,
        qualifier: String? = nil,
        installedAt: Date? = nil
    ) -> Package {
        let effectiveQualifier = qualifier ?? (manager == .pip ? "/usr/bin/python3" : nil)
        let qualifiedId: String
        if manager == .pip {
            qualifiedId = "pip:\(effectiveQualifier ?? ""):\(name)"
        } else {
            qualifiedId = "\(manager.rawValue)::\(name)"
        }
        return Package(
            id: qualifiedId,
            manager: manager,
            qualifier: effectiveQualifier,
            name: name,
            version: "1.0.0",
            installPath: nil,
            installedAt: installedAt,
            installedAtConfidence: installedAt != nil ? .high : .unknown,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    /// Builds a ShellHistoryCollector whose zsh history contains timed install commands.
    /// `commands` is a list of (rawCommand, secondsFromT0) pairs.
    private func shellCollector(
        commands: [(cmd: String, offset: TimeInterval)]
    ) -> ShellHistoryCollector {
        let lines = commands.map { pair -> String in
            let ts = Int(t0.timeIntervalSince1970 + pair.offset)
            return ": \(ts):0;\(pair.cmd)"
        }
        let content = lines.joined(separator: "\n")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".zsh_history"),
                data: Data(content.utf8)
            )
        }
        return ShellHistoryCollector(directoryAccess: provider, homeDirectory: home)
    }

    /// Builds a ShellHistoryCollector with a single bare (no timestamp) zsh entry.
    private func shellCollectorNoTimestamp(command: String) -> ShellHistoryCollector {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".zsh_history"),
                data: Data(command.utf8)
            )
        }
        return ShellHistoryCollector(directoryAccess: provider, homeDirectory: home)
    }

    /// Builds a ClaudeCodeLogCollector with a single JSONL line whose timestamp
    /// is t0 + `offset` seconds.
    private func claudeCollector(command: String, offset: TimeInterval) -> ClaudeCodeLogCollector {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tsStr = f.string(from: Date(timeIntervalSince1970: t0.timeIntervalSince1970 + offset))
        let jsonl = """
            {"sessionId":"s1","timestamp":"\(tsStr)","cwd":"/tmp/project","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"\(command)"}}]}}
            """
        let projectDir = home.appendingPathComponent(".claude/projects/-tmp-project")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: projectDir.appendingPathComponent("session.jsonl"),
                data: Data(jsonl.utf8)
            )
        }
        return ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home)
    }

    /// Builds a ClaudeCodeLogCollector whose JSONL line has no timestamp field.
    private func claudeCollectorNoTimestamp(command: String) -> ClaudeCodeLogCollector {
        let jsonl = """
            {"sessionId":"s1","cwd":"/tmp","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"\(command)"}}]}}
            """
        let projectDir = home.appendingPathComponent(".claude/projects/-tmp-project")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: projectDir.appendingPathComponent("session.jsonl"),
                data: Data(jsonl.utf8)
            )
        }
        return ClaudeCodeLogCollector(directoryAccess: provider, homeDirectory: home)
    }

    private func emptyShell() -> ShellHistoryCollector {
        ShellHistoryCollector(
            directoryAccess: InMemoryDirectoryAccessProvider.make { _ in },
            homeDirectory: home
        )
    }

    private func emptyClaude() -> ClaudeCodeLogCollector {
        ClaudeCodeLogCollector(
            directoryAccess: InMemoryDirectoryAccessProvider.make { _ in },
            homeDirectory: home
        )
    }

    private func emptyCodex() -> CodexLogCollector {
        CodexLogCollector(
            directoryAccess: InMemoryDirectoryAccessProvider.make { _ in },
            homeDirectory: home
        )
    }

    private func emptyOpenCode() -> OpenCodeLogCollector {
        OpenCodeLogCollector(
            databasePath: home.appendingPathComponent("opencode.db")
        )
    }

    @Test("PERF25-005: a cancelled aggregate collection publishes no partial evidence")
    func cancelledCollectionReturnsNoEvidence() async {
        let packages = (0..<5_000).map { index in
            makePackage("package-\(index)", installedAt: t0)
        }
        let collector = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        )
        let task = Task.detached {
            do { try await Task.sleep(for: .milliseconds(50)) } catch {}
            return collector.collect(packages: packages)
        }

        task.cancel()

        #expect(await task.value.isEmpty)
    }

    // MARK: - Confidence

    @Test("Claude Code match within ±1h sets .high confidence and populates claudeCodeContext")
    func highConfidenceClaudeCode() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: claudeCollector(command: "brew install ffmpeg", offset: 600),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pkg])
        #expect(results[0].claudeCodeContext != nil)
        #expect(results[0].overallConfidence == .high)
    }

    @Test("fs and shell match within 5 minutes sets .high confidence")
    func highConfidenceShellWithin5Min() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [("brew install ffmpeg", 200)]),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pkg])
        #expect(results[0].installCommand != nil)
        #expect(results[0].overallConfidence == .high)
    }

    @Test("fs and shell match more than 5 minutes apart sets .medium confidence")
    func mediumConfidenceShellBeyond5Min() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [("brew install ffmpeg", 400)]),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pkg])
        #expect(results[0].installCommand != nil)
        #expect(results[0].overallConfidence == .medium)
    }

    @Test("only fs mtime sets .low confidence with nil installCommand and claudeCodeContext")
    func lowConfidenceFsOnly() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pkg])
        #expect(results[0].installCommand == nil)
        #expect(results[0].claudeCodeContext == nil)
        #expect(results[0].overallConfidence == .low)
    }

    @Test("no fs mtime sets .unknown confidence regardless of other signals")
    func unknownConfidenceNoFsMtime() {
        let pkg = makePackage("ffmpeg", installedAt: nil)
        // Both signals present for the name — should still be .unknown without fsInstallTime.
        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [("brew install ffmpeg", 0)]),
            claudeCodeCollector: claudeCollector(command: "brew install ffmpeg", offset: 0),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pkg])
        #expect(results[0].overallConfidence == .unknown)
    }

    // MARK: - coInstalledWithin1h

    @Test("coInstalledWithin1h contains other packages within ±1h with no self-reference")
    func coInstalledWindow() {
        let ffmpeg  = makePackage("ffmpeg",  installedAt: t0)
        let libpng  = makePackage("libpng",  installedAt: t0.addingTimeInterval(1800))  // within window
        let openssl = makePackage("openssl", installedAt: t0.addingTimeInterval(7200))  // outside window
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [ffmpeg, libpng, openssl])

        let ffmpegEvidence = results.first { $0.packageId == "brew::ffmpeg" }!
        #expect(ffmpegEvidence.coInstalledWithin1h == ["brew::libpng"])
        #expect(ffmpegEvidence.coInstalledWithin1hTotalCount == 1)
        #expect(!ffmpegEvidence.coInstalledWithin1h.contains("brew::ffmpeg"))
        #expect(!ffmpegEvidence.coInstalledWithin1h.contains("brew::openssl"))
    }

    @Test("dense co-install windows persist a bounded sample and the full count")
    func denseCoInstalledWindowIsBounded() {
        let packages = (0..<5_000).map { index in
            makePackage("package-\(index)", installedAt: t0)
        }
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: packages)

        #expect(results.count == packages.count)
        #expect(results.allSatisfy { $0.coInstalledWithin1h.count == 20 })
        #expect(results.allSatisfy { $0.coInstalledWithin1hTotalCount == 4_999 })
        #expect(results.allSatisfy { !$0.coInstalledWithin1h.contains($0.packageId) })
    }

    // MARK: - Key isolation

    @Test("brew git install command does not match a pip package named git-something")
    func matchUsesManagerAndNameKey() {
        let pipPkg = makePackage("git-something", manager: .pip, installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [("brew install git", 100)]),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pipPkg])
        #expect(results[0].installCommand == nil)
    }

    @Test("CORE25-008: qualified Python commands disambiguate pip provenance by interpreter")
    func qualifiedPythonCommandDisambiguatesPipScopes() {
        let python311 = "/opt/homebrew/bin/python3.11"
        let python312 = "/opt/homebrew/bin/python3.12"
        let packages = [
            makePackage("httpx", manager: .pip, qualifier: python311, installedAt: t0),
            makePackage("httpx", manager: .pip, qualifier: python312, installedAt: t0),
        ]

        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [
                ("/opt/homebrew/bin/python3.11 -m pip install httpx", 60),
            ]),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: packages)

        let byPackage = Dictionary(uniqueKeysWithValues: results.map { ($0.packageId, $0) })
        #expect(byPackage["pip:\(python311):httpx"]?.installCommand != nil)
        #expect(byPackage["pip:\(python312):httpx"]?.installCommand == nil)
    }

    @Test("CORE25-008: versioned Python commands disambiguate Claude provenance")
    func versionedPythonCommandDisambiguatesClaudeScopes() {
        let python311 = "/opt/homebrew/bin/python3.11"
        let python312 = "/opt/homebrew/bin/python3.12"
        let packages = [
            makePackage("rich", manager: .pip, qualifier: python311, installedAt: t0),
            makePackage("rich", manager: .pip, qualifier: python312, installedAt: t0),
        ]

        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: claudeCollector(
                command: "python3.11 -m pip install rich",
                offset: 60
            ),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: packages)

        let byPackage = Dictionary(uniqueKeysWithValues: results.map { ($0.packageId, $0) })
        #expect(byPackage["pip:\(python311):rich"]?.claudeCodeContext != nil)
        #expect(byPackage["pip:\(python312):rich"]?.claudeCodeContext == nil)
    }

    @Test("CORE25-008: unqualified evidence remains a fallback outside another qualified scope")
    func unqualifiedEvidenceIsConservativeFallback() {
        let python311 = "/opt/homebrew/bin/python3.11"
        let python312 = "/opt/homebrew/bin/python3.12"
        let packages = [
            makePackage("my-package", manager: .pip, qualifier: python311, installedAt: t0),
            makePackage("my-package", manager: .pip, qualifier: python312, installedAt: t0),
        ]

        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [
                ("/opt/homebrew/bin/python3.11 -m pip install my_package", 180),
                ("pip install my.package", 30),
            ]),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: packages)

        let byPackage = Dictionary(uniqueKeysWithValues: results.map { ($0.packageId, $0) })
        #expect(
            byPackage["pip:\(python311):my-package"]?.installCommand?.command
                == "/opt/homebrew/bin/python3.11 -m pip install my_package"
        )
        #expect(
            byPackage["pip:\(python312):my-package"]?.installCommand?.command
                == "pip install my.package"
        )
    }

    @Test("CORE25-008: stale qualified evidence does not suppress timely unqualified fallback")
    func unqualifiedEvidenceFallbackAfterStaleQualifiedRecord() {
        let python311 = "/opt/homebrew/bin/python3.11"
        let package = makePackage(
            "httpx",
            manager: .pip,
            qualifier: python311,
            installedAt: t0
        )

        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [
                ("/opt/homebrew/bin/python3.11 -m pip install httpx", 7_200),
                ("pip install httpx", 30),
            ]),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [package])

        #expect(results[0].installCommand?.command == "pip install httpx")
    }

    // MARK: - Nil-timestamp exclusion

    @Test("nil-timestamp shell and Claude Code records are excluded from matching")
    func nilTimestampRecordsExcluded() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollectorNoTimestamp(command: "brew install ffmpeg"),
            claudeCodeCollector: claudeCollectorNoTimestamp(command: "brew install ffmpeg"),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pkg])
        #expect(results[0].installCommand == nil)
        #expect(results[0].claudeCodeContext == nil)
        // Only fs is present → .low
        #expect(results[0].overallConfidence == .low)
    }

    // MARK: - Claude Code preference

    @Test("when both shell and Claude Code match, claudeCodeContext is set and confidence is .high")
    func claudeCodePreferredOverShell() {
        // Shell at +200s (within 5 min, would be .high on its own).
        // Claude Code at +2000s (>5 min from fs, but within 1h — would be .medium without Claude).
        // Both should be populated; overall is .high because claudeCodeContext != nil.
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [("brew install ffmpeg", 200)]),
            claudeCodeCollector: claudeCollector(command: "brew install ffmpeg", offset: 2000),
            codexCollector: emptyCodex(),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pkg])
        #expect(results[0].installCommand != nil)
        #expect(results[0].claudeCodeContext != nil)
        #expect(results[0].overallConfidence == .high)
    }

    // MARK: - Codex + opencode context

    /// Builds a CodexLogCollector with a single exec_command line at t0 + `offset`
    /// seconds, inside a fixed date-based session directory.
    private func codexCollector(command: String, offset: TimeInterval) -> CodexLogCollector {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tsStr = f.string(from: Date(timeIntervalSince1970: t0.timeIntervalSince1970 + offset))
        let jsonl = """
            {"timestamp":"\(tsStr)","type":"session_meta","payload":{"id":"s1","cwd":"/tmp/project"}}
            {"timestamp":"\(tsStr)","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"\(command)\\"}"}}
            """
        let sessionFile = home
            .appendingPathComponent(".codex/sessions/2026/03/01/rollout-test.jsonl")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: sessionFile, data: Data(jsonl.utf8))
        }
        return CodexLogCollector(directoryAccess: provider, homeDirectory: home)
    }

    /// Builds an OpenCodeLogCollector backed by a temp on-disk SQLite db with one
    /// bash tool part at t0 + `offset` seconds.
    private func opencodeCollector(command: String, offset: TimeInterval) throws -> OpenCodeLogCollector {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-\(UUID().uuidString)/opencode.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let queue = try DatabaseQueue(path: dbURL.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT NOT NULL, title TEXT NOT NULL)")
            try db.execute(sql: "CREATE TABLE part (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL)")
            let ms = Int64((t0.timeIntervalSince1970 + offset) * 1_000)
            try db.execute(sql: "INSERT INTO session (id, directory, title) VALUES ('s1', '/tmp/project', 'Demo session')")
            try db.execute(sql: "INSERT INTO part (id, session_id, time_created, time_updated, data) VALUES ('p1', 's1', ?, ?, ?)", arguments: [ms, ms, #"{"type":"tool","tool":"bash","state":{"input":{"command":"\#(command)"}}}"#])
        }
        return OpenCodeLogCollector(databasePath: dbURL)
    }

    @Test("Phase D: codex exec_command within ±1h sets .high confidence and populates codexContext")
    func codexContextPopulatesEvidence() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude(),
            codexCollector: codexCollector(command: "brew install ffmpeg", offset: 600),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: [pkg])
        #expect(results[0].codexContext != nil)
        #expect(results[0].overallConfidence == .high)
        #expect(wasInstalledByAIAssistant(results[0]))
    }

    @Test("Phase D: opencode bash part within ±1h sets .high confidence and populates opencodeContext")
    func opencodeContextPopulatesEvidence() throws {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let collector = try opencodeCollector(command: "brew install ffmpeg", offset: 600)
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude(),
            codexCollector: emptyCodex(),
            opencodeCollector: collector
        ).collect(packages: [pkg])
        #expect(results[0].opencodeContext != nil)
        #expect(results[0].overallConfidence == .high)
        #expect(wasInstalledByAIAssistant(results[0]))
    }

    @Test("Phase D: qualified codex Python commands disambiguate pip provenance by interpreter")
    func codexQualifiedScopeDisambiguatesPipScopes() {
        let python311 = "/opt/homebrew/bin/python3.11"
        let python312 = "/opt/homebrew/bin/python3.12"
        let packages = [
            makePackage("rich", manager: .pip, qualifier: python311, installedAt: t0),
            makePackage("rich", manager: .pip, qualifier: python312, installedAt: t0),
        ]

        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude(),
            codexCollector: codexCollector(command: "python3.11 -m pip install rich", offset: 60),
            opencodeCollector: emptyOpenCode()
        ).collect(packages: packages)

        let byPackage = Dictionary(uniqueKeysWithValues: results.map { ($0.packageId, $0) })
        #expect(byPackage["pip:\(python311):rich"]?.codexContext != nil)
        #expect(byPackage["pip:\(python312):rich"]?.codexContext == nil)
    }
}
