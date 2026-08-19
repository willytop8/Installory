import Foundation
import GRDB

/// Per-package user annotations: hidden, pinned, and a free-form note.
///
/// These are user intent layered on top of the inventory, keyed by the same
/// package ID format as ``Package``. They survive package scans: hiding a
/// package keeps it out of the inventory lists and cleanup candidates until
/// the user unhides it, and a note travels with the package regardless of
/// version changes.
public struct PackageUserState: Codable, Sendable, Equatable {
    /// The `{manager}:{qualifier}:{name}` ID of the annotated package.
    public var packageId: String
    /// When true the package is excluded from inventory lists and cleanup.
    public var isHidden: Bool
    /// When true the package sorts to the top of the inventory list.
    public var isPinned: Bool
    /// An optional free-form user note.
    public var note: String?
    /// Last time any of the annotations changed.
    public var updatedAt: Date

    public init(
        packageId: String,
        isHidden: Bool = false,
        isPinned: Bool = false,
        note: String? = nil,
        updatedAt: Date
    ) {
        self.packageId = packageId
        self.isHidden = isHidden
        self.isPinned = isPinned
        self.note = note
        self.updatedAt = updatedAt
    }
}

extension PackageUserState: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "package_user_state"

    public init(row: Row) throws {
        packageId = row["package_id"]
        isHidden = (row["is_hidden"] as Int64) != 0
        isPinned = (row["is_pinned"] as Int64) != 0
        note = row["note"] as String?
        updatedAt = Date(timeIntervalSince1970: row["updated_at"] as Double)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["package_id"] = packageId
        container["is_hidden"] = isHidden ? 1 : 0
        container["is_pinned"] = isPinned ? 1 : 0
        container["note"] = note
        container["updated_at"] = updatedAt.timeIntervalSince1970
    }
}
