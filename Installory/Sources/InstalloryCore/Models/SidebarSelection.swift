import Foundation

public enum SidebarSelection: Hashable, Sendable {
    case all
    case manager(PackageManager)
    case readOnly
    case duplicates
    case orphans
    case diskUsage
    case aiInstalled
    case snapshot(UUID)
}

extension SidebarSelection {
    public var userDefaultsKey: String {
        switch self {
        case .all: "all"
        case .manager(let m): "manager.\(m.rawValue)"
        case .readOnly: "readOnly"
        case .duplicates: "duplicates"
        case .orphans: "orphans"
        case .diskUsage: "diskUsage"
        case .aiInstalled: "aiInstalled"
        case .snapshot: ""  // snapshot selections are never persisted
        }
    }

    public init?(userDefaultsKey: String) {
        switch userDefaultsKey {
        case "all": self = .all
        case "readOnly": self = .readOnly
        case "duplicates": self = .duplicates
        case "orphans": self = .orphans
        case "diskUsage": self = .diskUsage
        case "aiInstalled": self = .aiInstalled
        default:
            guard userDefaultsKey.hasPrefix("manager.") else { return nil }
            let raw = String(userDefaultsKey.dropFirst("manager.".count))
            guard let mgr = PackageManager(rawValue: raw) else { return nil }
            self = .manager(mgr)
        }
    }
}

extension [Package] {
    /// Returns packages whose name, manager scope, or install path matches the
    /// query, preserving input order. Whitespace-only queries are inactive.
    public func matching(query: String) -> [Package] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self }
        return filter { $0.matchesSearchQuery(query) }
    }

    /// Returns packages matching `selection` and `query`, preserving order.
    /// The sort step is the caller's responsibility.
    public func filtered(by selection: SidebarSelection?, query: String) -> [Package] {
        var result = self
        switch selection {
        case nil, .all:
            break
        case .manager(let m):
            result = result.filter { $0.manager == m }
        case .readOnly:
            result = result.filter(\.isReadOnly)
        case .duplicates:
            // DuplicatesView reads crossManagerDuplicates() directly; filteredPackages is not consulted.
            return []
        case .orphans:
            // OrphansView reads coordinator.orphanedPackages directly; filteredPackages is not consulted.
            return []
        case .diskUsage:
            // DiskUsageView reads a generation-keyed aggregate instead of package rows.
            return []
        case .aiInstalled:
            // AIInstalledView reads coordinator.aiInstalledPackages directly; filteredPackages is not consulted.
            return []
        case .snapshot(_):
            // Snapshot content is rendered by SnapshotContentView, not this filter.
            return []
        }
        return result.matching(query: query)
    }
}

extension Package {
    /// Shared in-memory search predicate for every live-inventory view.
    public func matchesSearchQuery(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || qualifier?.localizedCaseInsensitiveContains(query) == true
            || installPath?.path.localizedCaseInsensitiveContains(query) == true
    }
}
