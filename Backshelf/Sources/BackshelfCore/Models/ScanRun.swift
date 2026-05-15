import Foundation
import GRDB

/// A diagnostic record of one invocation of the scanner coordinator.
///
/// Stored for diagnostics only. The `perManagerResults` dictionary is
/// serialized as JSON with a predictable, human-readable shape so that
/// support sessions can inspect the raw SQLite without a special tool.
public struct ScanRun: Identifiable, Codable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let completedAt: Date?
    /// Result per manager, including counts, durations, and failure reasons.
    public let perManagerResults: [PackageManager: ScannerStatus]
}

/// The outcome of a single scanner's execution during a scan run.
///
/// Explicit `Codable` implementation (not auto-synthesized) so the JSON
/// shape is predictable and debuggable: `{"type":"succeeded","count":5,"durationMs":120}`.
public enum ScannerStatus: Equatable, Sendable {
    case succeeded(count: Int, durationMs: Int)
    case failed(reason: String, durationMs: Int)
    case timedOut(durationMs: Int)
    case skipped(reason: String)
}

// MARK: - ScannerStatus Codable

extension ScannerStatus: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, count, durationMs, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)
        switch type_ {
        case "succeeded":
            self = .succeeded(
                count: try container.decode(Int.self, forKey: .count),
                durationMs: try container.decode(Int.self, forKey: .durationMs)
            )
        case "failed":
            self = .failed(
                reason: try container.decode(String.self, forKey: .reason),
                durationMs: try container.decode(Int.self, forKey: .durationMs)
            )
        case "timedOut":
            self = .timedOut(durationMs: try container.decode(Int.self, forKey: .durationMs))
        case "skipped":
            self = .skipped(reason: try container.decode(String.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown ScannerStatus type '\(type_)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .succeeded(let count, let ms):
            try container.encode("succeeded", forKey: .type)
            try container.encode(count, forKey: .count)
            try container.encode(ms, forKey: .durationMs)
        case .failed(let reason, let ms):
            try container.encode("failed", forKey: .type)
            try container.encode(reason, forKey: .reason)
            try container.encode(ms, forKey: .durationMs)
        case .timedOut(let ms):
            try container.encode("timedOut", forKey: .type)
            try container.encode(ms, forKey: .durationMs)
        case .skipped(let reason):
            try container.encode("skipped", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

// MARK: - GRDB

extension ScanRun: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "scan_runs"

    public init(row: Row) throws {
        let idStr: String = row["id"]
        guard let uuid = UUID(uuidString: idStr) else {
            throw DatabaseError(message: "scan_runs.id '\(idStr)' is not a valid UUID")
        }
        id = uuid
        startedAt = Date(timeIntervalSince1970: row["started_at"] as Double)

        if let ts: Double = row["completed_at"] {
            completedAt = Date(timeIntervalSince1970: ts)
        } else {
            completedAt = nil
        }

        let resultsJSON: String = row["per_manager_results"]
        guard let data = resultsJSON.data(using: .utf8) else {
            throw DatabaseError(message: "scan_runs.per_manager_results is not valid UTF-8")
        }
        perManagerResults = try JSONDecoder().decode([PackageManager: ScannerStatus].self, from: data)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["started_at"] = startedAt.timeIntervalSince1970
        container["completed_at"] = completedAt.map { $0.timeIntervalSince1970 }
        let data = try JSONEncoder().encode(perManagerResults)
        container["per_manager_results"] = String(data: data, encoding: .utf8)
    }
}
