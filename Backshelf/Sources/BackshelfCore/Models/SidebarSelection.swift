public enum SidebarSelection: Hashable, Sendable {
    case all
    case manager(PackageManager)
    case readOnly
}

extension SidebarSelection {
    public var userDefaultsKey: String {
        switch self {
        case .all: "all"
        case .manager(let m): "manager.\(m.rawValue)"
        case .readOnly: "readOnly"
        }
    }

    public init?(userDefaultsKey: String) {
        switch userDefaultsKey {
        case "all": self = .all
        case "readOnly": self = .readOnly
        default:
            guard userDefaultsKey.hasPrefix("manager.") else { return nil }
            let raw = String(userDefaultsKey.dropFirst("manager.".count))
            guard let mgr = PackageManager(rawValue: raw) else { return nil }
            self = .manager(mgr)
        }
    }
}

extension [Package] {
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
        }
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return result
    }
}
