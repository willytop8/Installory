import Foundation
import GRDB

/// Structured evidence for when and why a package was installed.
///
/// Gathered by `ProvenanceCollector` from up to three signals: filesystem
/// timestamps, shell history, and agent session logs (Claude Code, Codex,
/// opencode). Stored as a JSON blob in the `provenance_evidence.payload`
/// column, with `collected_at` and `overall_confidence` also extracted as
/// top-level columns so callers can query them without decoding the payload.
public struct ProvenanceEvidence: Codable, Sendable {
    public let packageId: String

    // MARK: Filesystem signal

    /// Best install-time estimate derived from on-disk metadata.
    public let fsInstallTime: Date?
    /// Source of the filesystem timestamp, e.g. `"INSTALL_RECEIPT.json"` or `"dist-info mtime"`.
    public let fsInstallTimeSource: String?

    // MARK: Shell history signal

    public let installCommand: InstallCommandRecord?

    // MARK: Agent-session signals

    /// Context from a Claude Code session that triggered the install.
    public let claudeCodeContext: ClaudeCodeContext?
    /// Context from a Codex session that triggered the install.
    public let codexContext: CodexContext?
    /// Context from an opencode session that triggered the install.
    public let opencodeContext: OpenCodeContext?

    // MARK: Derived

    /// Projects that were being actively worked on near the install time.
    public let nearbyProjects: [NearbyProject]
    /// IDs of packages installed within one hour of this one.
    public let coInstalledWithin1h: [String]
    /// Total packages installed within the same one-hour window.
    ///
    /// The ID list is a bounded sample so dense installs do not create enormous
    /// persistence payloads. This field is optional for backward compatibility
    /// with evidence collected before the total was recorded.
    public let coInstalledWithin1hTotalCount: Int?

    public let overallConfidence: Confidence
    public let collectedAt: Date

    public init(
        packageId: String,
        fsInstallTime: Date?,
        fsInstallTimeSource: String?,
        installCommand: InstallCommandRecord?,
        claudeCodeContext: ClaudeCodeContext?,
        codexContext: CodexContext? = nil,
        opencodeContext: OpenCodeContext? = nil,
        nearbyProjects: [NearbyProject],
        coInstalledWithin1h: [String],
        coInstalledWithin1hTotalCount: Int? = nil,
        overallConfidence: Confidence,
        collectedAt: Date
    ) {
        self.packageId = packageId
        self.fsInstallTime = fsInstallTime
        self.fsInstallTimeSource = fsInstallTimeSource
        self.installCommand = installCommand
        self.claudeCodeContext = claudeCodeContext
        self.codexContext = codexContext
        self.opencodeContext = opencodeContext
        self.nearbyProjects = nearbyProjects
        self.coInstalledWithin1h = coInstalledWithin1h
        self.coInstalledWithin1hTotalCount = coInstalledWithin1hTotalCount
        self.overallConfidence = overallConfidence
        self.collectedAt = collectedAt
    }
}

// MARK: - Nested types

extension ProvenanceEvidence {
    /// The user's interactive shell at the time of the install command.
    ///
    /// Nested here because `Shell` is only needed to describe a provenance
    /// signal. Promote to a top-level type only if something outside
    /// provenance needs it.
    public enum Shell: String, Codable, Sendable {
        case zsh
        case bash
        case fish
    }

    /// A shell-history record of the command that installed a package.
    public struct InstallCommandRecord: Codable, Sendable {
        /// When the install command was executed, if recoverable from history.
        /// nil when the shell does not record timestamps (bash without HISTTIMEFORMAT,
        /// fish entries without `when`, or malformed zsh extended-format lines).
        public let timestamp: Date?
        /// The raw shell command, e.g. `"pip install openai-whisper"`.
        public let command: String
        public let shell: Shell
        /// Working directory at the time, if recoverable from history format.
        public let cwd: String?

        public init(timestamp: Date?, command: String, shell: Shell, cwd: String?) {
            self.timestamp = timestamp
            self.command = command
            self.shell = shell
            self.cwd = cwd
        }
    }

    /// Context extracted from a Claude Code session log that triggered the install.
    public struct ClaudeCodeContext: Codable, Sendable, Equatable {
        public let sessionId: String
        public let projectPath: String
        /// Summary line from `sessions-index.json`, if present.
        public let sessionSummary: String?
        /// First user message in the session, truncated.
        public let firstUserMessage: String?
        /// The exact `Bash` tool_use invocation that installed the package.
        public let bashInvocation: String
        /// When the Bash invocation ran. `nil` when the JSONL timestamp field is
        /// absent or malformed — emitting nil is preferred over the epoch fallback.
        public let timestamp: Date?

        public init(
            sessionId: String,
            projectPath: String,
            sessionSummary: String?,
            firstUserMessage: String?,
            bashInvocation: String,
            timestamp: Date?
        ) {
            self.sessionId = sessionId
            self.projectPath = projectPath
            self.sessionSummary = sessionSummary
            self.firstUserMessage = firstUserMessage
            self.bashInvocation = bashInvocation
            self.timestamp = timestamp
        }
    }

    /// Context extracted from a Codex session log (`~/.codex/sessions/**/rollout-*.jsonl`)
    /// that triggered the install.
    ///
    /// Codex sessions do not carry a per-project summary index or a recoverable
    /// first user message, so those fields remain nil for Codex records.
    public struct CodexContext: Codable, Sendable, Equatable {
        public let sessionId: String
        public let projectPath: String
        public let sessionSummary: String?
        public let firstUserMessage: String?
        /// The exact `exec_command` invocation that installed the package.
        public let bashInvocation: String
        public let timestamp: Date?

        public init(
            sessionId: String,
            projectPath: String,
            sessionSummary: String?,
            firstUserMessage: String?,
            bashInvocation: String,
            timestamp: Date?
        ) {
            self.sessionId = sessionId
            self.projectPath = projectPath
            self.sessionSummary = sessionSummary
            self.firstUserMessage = firstUserMessage
            self.bashInvocation = bashInvocation
            self.timestamp = timestamp
        }
    }

    /// Context extracted from an opencode session (read from the local
    /// `opencode.db` SQLite database) that triggered the install.
    ///
    /// The session title is used as the summary; opencode does not expose a
    /// recoverable first user message for every session.
    public struct OpenCodeContext: Codable, Sendable, Equatable {
        public let sessionId: String
        public let projectPath: String
        public let sessionSummary: String?
        public let firstUserMessage: String?
        /// The exact `bash` tool input that installed the package.
        public let bashInvocation: String
        public let timestamp: Date?

        public init(
            sessionId: String,
            projectPath: String,
            sessionSummary: String?,
            firstUserMessage: String?,
            bashInvocation: String,
            timestamp: Date?
        ) {
            self.sessionId = sessionId
            self.projectPath = projectPath
            self.sessionSummary = sessionSummary
            self.firstUserMessage = firstUserMessage
            self.bashInvocation = bashInvocation
            self.timestamp = timestamp
        }
    }

    /// A nearby project that was being actively modified around the install time.
    public struct NearbyProject: Codable, Sendable {
        public let path: String
        public let modifiedFileCount: Int
        public let gitCommitsThatDay: Int

        public init(path: String, modifiedFileCount: Int, gitCommitsThatDay: Int) {
            self.path = path
            self.modifiedFileCount = modifiedFileCount
            self.gitCommitsThatDay = gitCommitsThatDay
        }
    }
}

// MARK: - GRDB

/// Shared JSON encoder/decoder for provenance payload serialization.
/// `secondsSince1970` keeps date representation consistent with SQLite REAL columns.
private let provenanceEncoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .secondsSince1970
    return enc
}()

private let provenanceDecoder: JSONDecoder = {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .secondsSince1970
    return dec
}()

extension ProvenanceEvidence: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "provenance_evidence"

    /// Decodes from the `payload` JSON blob in the DB row.
    public init(row: Row) throws {
        let payloadJSON: String = row["payload"]
        guard let data = payloadJSON.data(using: .utf8) else {
            throw DatabaseError(message: "provenance_evidence.payload is not valid UTF-8")
        }
        let decoded = try provenanceDecoder.decode(ProvenanceEvidence.self, from: data)
        // Protect presentation paths when opening evidence written by versions
        // predating the centralized redaction boundary.
        self = ProvenanceRedactor().redact(decoded)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        // Persist only the redacted form even when callers bypass ProvenanceDAO
        // and save the record through GRDB directly.
        let safeEvidence = ProvenanceRedactor().redact(self)
        container["package_id"] = safeEvidence.packageId
        let data = try provenanceEncoder.encode(safeEvidence)
        container["payload"] = String(data: data, encoding: .utf8)
        container["collected_at"] = safeEvidence.collectedAt.timeIntervalSince1970
        container["overall_confidence"] = safeEvidence.overallConfidence.rawValue
    }
}
