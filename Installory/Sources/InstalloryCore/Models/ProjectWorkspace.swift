import Foundation

/// The language or tool a project workspace appears to target, derived from
/// the marker files found directly inside it.
public enum ProjectWorkspaceKind: String, Sendable, Equatable {
    case node
    case python
    case rust
    case xcode
    case git
}

/// A project directory discovered under a user-granted root.
///
/// Workspaces are inventoried read-only and in-memory only. They are never
/// persisted and never become cleanup targets; the view offers a "reveal in
/// Finder" affordance but no removal automation.
public struct ProjectWorkspace: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { path.path }
    public let path: URL
    public let name: String
    public let kind: ProjectWorkspaceKind
    public let sizeBytes: Int64?
    public let lastModifiedAt: Date?

    public init(
        path: URL,
        name: String,
        kind: ProjectWorkspaceKind,
        sizeBytes: Int64?,
        lastModifiedAt: Date?
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.lastModifiedAt = lastModifiedAt
    }
}
