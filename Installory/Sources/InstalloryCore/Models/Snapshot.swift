import Foundation
import GRDB

/// A point-in-time export manifest of all installed packages.
///
/// A snapshot is a record, not an executable state. Installory never restores
/// a snapshot itself — it generates a reinstall shell script from the
/// snapshot that the user runs in Terminal.
public struct Snapshot: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let reason: SnapshotReason
    /// Optional free-text note the user attached to this snapshot.
    public let note: String?
    public let payload: SnapshotPayload
}

/// Why the snapshot was created.
public enum SnapshotReason: String, Codable, Sendable {
    case manual
    case preCleanup
    case preUninstall
    case autoFirstScan
}

/// The inventory recorded inside a snapshot.
///
/// Uses `[PackageManager: [SnapshotPackage]]`. Custom `Codable` ensures
/// the JSON keys are the manager's `rawValue` strings rather than the
/// Swift-default array-of-pairs encoding.
public struct SnapshotPayload: Sendable {
    public let managers: [PackageManager: [SnapshotPackage]]

    public init(managers: [PackageManager: [SnapshotPackage]]) {
        self.managers = managers
    }
}

/// A minimal package record stored inside a snapshot payload.
public struct SnapshotPackage: Identifiable, Codable, Sendable {
    /// Composite of name and qualifier so that pip packages across different interpreters
    /// with the same name don't collide when used as SwiftUI ForEach identifiers.
    public var id: String { "\(name)|\(qualifier ?? "")" }
    public let name: String
    public let version: String
    /// Interpreter path for pip packages; nil for all other managers.
    public let qualifier: String?
    public let isExplicit: Bool
}

// MARK: - SnapshotPayload custom Codable

extension SnapshotPayload: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ManagerKey.self)
        for (manager, packages) in managers {
            let key = ManagerKey(stringValue: manager.rawValue)
            try container.encode(packages, forKey: key)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ManagerKey.self)
        var result: [PackageManager: [SnapshotPackage]] = [:]
        for key in container.allKeys {
            // Unknown manager keys are silently skipped for forward compatibility
            // (a snapshot written by a newer version may include post-v0 managers).
            guard let manager = PackageManager(rawValue: key.stringValue) else { continue }
            result[manager] = try container.decode([SnapshotPackage].self, forKey: key)
        }
        managers = result
    }

    /// Dynamic `CodingKey` backed by `PackageManager.rawValue` strings.
    private struct ManagerKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

// MARK: - GRDB

private let snapshotEncoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .secondsSince1970
    return enc
}()

private let snapshotDecoder: JSONDecoder = {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .secondsSince1970
    return dec
}()

extension Snapshot: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "snapshots"

    public init(row: Row) throws {
        let idStr: String = row["id"]
        guard let uuid = UUID(uuidString: idStr) else {
            throw DatabaseError(message: "snapshots.id '\(idStr)' is not a valid UUID")
        }
        id = uuid
        createdAt = Date(timeIntervalSince1970: row["created_at"] as Double)

        let reasonStr: String = row["reason"]
        guard let r = SnapshotReason(rawValue: reasonStr) else {
            throw DatabaseError(message: "Unknown SnapshotReason '\(reasonStr)' in snapshots row")
        }
        reason = r
        note = row["note"]

        let payloadJSON: String = row["payload"]
        guard let payloadData = payloadJSON.data(using: .utf8) else {
            throw DatabaseError(message: "snapshots.payload is not valid UTF-8")
        }
        payload = try snapshotDecoder.decode(SnapshotPayload.self, from: payloadData)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["created_at"] = createdAt.timeIntervalSince1970
        container["reason"] = reason.rawValue
        container["note"] = note
        let payloadData = try snapshotEncoder.encode(payload)
        container["payload"] = String(data: payloadData, encoding: .utf8)
    }
}
