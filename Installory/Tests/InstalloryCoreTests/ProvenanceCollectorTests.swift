import Testing
import Foundation
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
        installedAt: Date? = nil
    ) -> Package {
        let qualifiedId: String
        if manager == .pip {
            qualifiedId = "pip::/usr/bin/python3:\(name)"
        } else {
            qualifiedId = "\(manager.rawValue)::\(name)"
        }
        return Package(
            id: qualifiedId,
            manager: manager,
            qualifier: manager == .pip ? "/usr/bin/python3" : nil,
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

    // MARK: - Confidence

    @Test("Claude Code match within ±1h sets .high confidence and populates claudeCodeContext")
    func highConfidenceClaudeCode() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: claudeCollector(command: "brew install ffmpeg", offset: 600)
        ).collect(packages: [pkg])
        #expect(results[0].claudeCodeContext != nil)
        #expect(results[0].overallConfidence == .high)
    }

    @Test("fs and shell match within 5 minutes sets .high confidence")
    func highConfidenceShellWithin5Min() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [("brew install ffmpeg", 200)]),
            claudeCodeCollector: emptyClaude()
        ).collect(packages: [pkg])
        #expect(results[0].installCommand != nil)
        #expect(results[0].overallConfidence == .high)
    }

    @Test("fs and shell match more than 5 minutes apart sets .medium confidence")
    func mediumConfidenceShellBeyond5Min() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [("brew install ffmpeg", 400)]),
            claudeCodeCollector: emptyClaude()
        ).collect(packages: [pkg])
        #expect(results[0].installCommand != nil)
        #expect(results[0].overallConfidence == .medium)
    }

    @Test("only fs mtime sets .low confidence with nil installCommand and claudeCodeContext")
    func lowConfidenceFsOnly() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude()
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
            claudeCodeCollector: claudeCollector(command: "brew install ffmpeg", offset: 0)
        ).collect(packages: [pkg])
        #expect(results[0].overallConfidence == .unknown)
    }

    // MARK: - coInstalledWithin1h

    @Test("coInstalledWithin1h contains other packages within ±1h, sorted, no self-reference")
    func coInstalledWindow() {
        let ffmpeg  = makePackage("ffmpeg",  installedAt: t0)
        let libpng  = makePackage("libpng",  installedAt: t0.addingTimeInterval(1800))  // within window
        let openssl = makePackage("openssl", installedAt: t0.addingTimeInterval(7200))  // outside window
        let results = ProvenanceCollector(
            shellCollector: emptyShell(),
            claudeCodeCollector: emptyClaude()
        ).collect(packages: [ffmpeg, libpng, openssl])

        let ffmpegEvidence = results.first { $0.packageId == "brew::ffmpeg" }!
        #expect(ffmpegEvidence.coInstalledWithin1h == ["brew::libpng"])
        #expect(!ffmpegEvidence.coInstalledWithin1h.contains("brew::ffmpeg"))
        #expect(!ffmpegEvidence.coInstalledWithin1h.contains("brew::openssl"))
    }

    // MARK: - Key isolation

    @Test("brew git install command does not match a pip package named git-something")
    func matchUsesManagerAndNameKey() {
        let pipPkg = makePackage("git-something", manager: .pip, installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollector(commands: [("brew install git", 100)]),
            claudeCodeCollector: emptyClaude()
        ).collect(packages: [pipPkg])
        #expect(results[0].installCommand == nil)
    }

    // MARK: - Nil-timestamp exclusion

    @Test("nil-timestamp shell and Claude Code records are excluded from matching")
    func nilTimestampRecordsExcluded() {
        let pkg = makePackage("ffmpeg", installedAt: t0)
        let results = ProvenanceCollector(
            shellCollector: shellCollectorNoTimestamp(command: "brew install ffmpeg"),
            claudeCodeCollector: claudeCollectorNoTimestamp(command: "brew install ffmpeg")
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
            claudeCodeCollector: claudeCollector(command: "brew install ffmpeg", offset: 2000)
        ).collect(packages: [pkg])
        #expect(results[0].installCommand != nil)
        #expect(results[0].claudeCodeContext != nil)
        #expect(results[0].overallConfidence == .high)
    }
}
