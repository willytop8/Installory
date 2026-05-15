import Foundation
import GRDB

/// Structured evidence for when and why a package was installed.
///
/// Gathered by `ProvenanceCollector` from up to three signals: filesystem
/// timestamps, shell history, and Claude Code session logs. Stored as a
/// JSON blob in the `provenance_evidence.payload` column, with
/// `collected_at` and `overall_confidence` also extracted as top-level
/// columns for indexed queries.
public struct ProvenanceEvidence: Codable, Sendable {
    public let packageId: String

    // MARK: Filesystem signal

    /// Best install-time estimate derived from on-disk metadata.
    public let fsInstallTime: Date?
    /// Source of the filesystem timestamp, e.g. `"INSTALL_RECEIPT.json"` or `"dist-info mtime"`.
    public let fsInstallTimeSource: String?

    // MARK: Shell history signal

    public let installCommand: InstallCommandRecord?

    // MARK: Claude Code signal

    public let claudeCodeContext: ClaudeCodeContext?

    // MARK: Derived

    /// Projects that were being actively worked on near the install time.
    public let nearbyProjects: [NearbyProject]
    /// IDs of packages installed within one hour of this one.
    public let coInstalledWithin1h: [String]

    public let overallConfidence: Confidence
    public let collectedAt: Date
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
        public let timestamp: Date
        /// The raw shell command, e.g. `"pip install openai-whisper"`.
        public let command: String
        public let shell: Shell
        /// Working directory at the time, if recoverable from history format.
        public let cwd: String?
    }

    /// Context extracted from a Claude Code session log that triggered the install.
    public struct ClaudeCodeContext: Codable, Sendable {
        public let sessionId: String
        public let projectPath: String
        /// Summary line from `sessions-index.json`, if present.
        public let sessionSummary: String?
        /// First user message in the session, truncated.
        public let firstUserMessage: String?
        /// The exact `Bash` tool_use invocation that installed the package.
        public let bashInvocation: String
        public let timestamp: Date
    }

    /// A nearby project that was being actively modified around the install time.
    public struct NearbyProject: Codable, Sendable {
        public let path: String
        public let modifiedFileCount: Int
        public let gitCommitsThatDay: Int
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
        self = try provenanceDecoder.decode(ProvenanceEvidence.self, from: data)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["package_id"] = packageId
        let data = try provenanceEncoder.encode(self)
        container["payload"] = String(data: data, encoding: .utf8)
        container["collected_at"] = collectedAt.timeIntervalSince1970
        container["overall_confidence"] = overallConfidence.rawValue
    }
}
