import BackshelfCore
import Foundation

enum PackageSortOrder: String, CaseIterable, Sendable {
    case recentlyInstalled
    case nameAscending
    case managerThenName

    var displayName: String {
        switch self {
        case .recentlyInstalled: "Recently Installed"
        case .nameAscending: "Name (A–Z)"
        case .managerThenName: "Manager, then Name"
        }
    }
}

extension [Package] {
    func sorted(by order: PackageSortOrder) -> [Package] {
        switch order {
        case .recentlyInstalled:
            sorted { ($0.installedAt ?? .distantPast) > ($1.installedAt ?? .distantPast) }
        case .nameAscending:
            sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .managerThenName:
            sorted {
                if $0.manager.rawValue != $1.manager.rawValue {
                    return $0.manager.rawValue < $1.manager.rawValue
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }
}
