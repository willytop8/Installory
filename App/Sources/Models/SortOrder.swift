import InstalloryCore
import Foundation

enum PackageSortOrder: String, CaseIterable, Sendable {
    case recentlyInstalled
    case nameAscending
    case managerThenName
    /// Largest `sizeBytes` first; packages with unknown size sink to the end.
    case largestFirst
    /// Oldest `installedAt` first (earliest date first); unknown dates sink to the end.
    case oldestFirst
    /// Highest combined cleanup score (age + size) first. Packages in the
    /// `.unknown` bucket (no size AND no date) are appended at the end.
    /// This is not "most deletable" — it is "oldest and/or largest". Installory
    /// has no usage telemetry and cannot determine whether a package is unused.
    case cleanupCandidates

    var displayName: String {
        switch self {
        case .recentlyInstalled:  "Recently Installed"
        case .nameAscending:      "Name (A\u{2013}Z)"
        case .managerThenName:    "Manager, then Name"
        case .largestFirst:       "Largest First"
        case .oldestFirst:        "Oldest First"
        case .cleanupCandidates:  "Cleanup Candidates"
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
        case .largestFirst:
            sorted { ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1) }
        case .oldestFirst:
            sorted { ($0.installedAt ?? .distantFuture) < ($1.installedAt ?? .distantFuture) }
        case .cleanupCandidates:
            cleanupScores(for: self, now: Date()).map(\.package)
        }
    }
}
