import Foundation
import InstalloryCore

/// The two presentations available for the ordinary live inventory.
enum InventoryViewMode: String, CaseIterable, Codable, Hashable, Sendable {
    case list
    case table
}

/// A stable, persistence-safe identifier for each sortable inventory column.
enum PackageTableSortColumn: String, CaseIterable, Codable, Hashable, Sendable {
    case name
    case manager
    case version
    case size
    case installed
}

/// User-facing sort direction. Unlike `Foundation.SortOrder`, these raw values
/// remain explicit and stable in UserDefaults JSON.
enum PackageTableSortDirection: String, Codable, Hashable, Sendable {
    case ascending
    case descending
}

/// A native SwiftUI `Table` comparator whose persisted form contains only a
/// validated column raw value and direction raw value.
///
/// `compare` deliberately compares only the selected column. Descriptor
/// priority and the final ascending package-identity tie-break are applied by
/// `sortedForTable(using:)` so a primary descriptor never masks a secondary.
struct PackageTableSortDescriptor: Codable, Equatable, Hashable, Sendable, SortComparator {
    var column: PackageTableSortColumn
    var direction: PackageTableSortDirection

    init(
        column: PackageTableSortColumn,
        direction: PackageTableSortDirection = .ascending
    ) {
        self.column = column
        self.direction = direction
    }

    /// The safe default for missing or malformed persisted table sorting.
    static let defaultOrder: [PackageTableSortDescriptor] = [
        PackageTableSortDescriptor(column: .name),
    ]

    /// Bridge used by SwiftUI's native table sorting API.
    var order: SortOrder {
        get { direction == .ascending ? .forward : .reverse }
        set { direction = newValue == .forward ? .ascending : .descending }
    }

    func compare(_ lhs: Package, _ rhs: Package) -> ComparisonResult {
        switch column {
        case .name:
            return directed(lhs.name.localizedCaseInsensitiveCompare(rhs.name))

        case .manager:
            let displayComparison = lhs.manager.displayName.localizedCaseInsensitiveCompare(
                rhs.manager.displayName
            )
            if displayComparison != .orderedSame {
                return directed(displayComparison)
            } else {
                return directed(lhs.manager.rawValue.compare(rhs.manager.rawValue))
            }

        case .version:
            return directed(lhs.version.localizedStandardCompare(rhs.version))

        case .size:
            return compareOptional(lhs.sizeBytes, rhs.sizeBytes)

        case .installed:
            return compareOptional(lhs.installedAt, rhs.installedAt)
        }
    }

    /// Accept only a non-empty sequence with one descriptor per known column.
    /// Any malformed sequence falls back as a whole instead of partially
    /// applying corrupt user state.
    static func validated(
        _ descriptors: [PackageTableSortDescriptor]
    ) -> [PackageTableSortDescriptor] {
        guard !descriptors.isEmpty,
              descriptors.count <= PackageTableSortColumn.allCases.count,
              Set(descriptors.map(\.column)).count == descriptors.count else {
            return defaultOrder
        }
        return descriptors
    }

    private func directed(_ result: ComparisonResult) -> ComparisonResult {
        guard direction == .descending else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    /// Unknown values always follow known values, independently of direction.
    private func compareOptional<Value: Comparable>(
        _ lhs: Value?,
        _ rhs: Value?
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.none, .none):
            return .orderedSame
        case (.none, .some):
            return .orderedDescending
        case (.some, .none):
            return .orderedAscending
        case let (.some(lhs), .some(rhs)):
            if lhs == rhs { return .orderedSame }
            return directed(lhs < rhs ? .orderedAscending : .orderedDescending)
        }
    }
}

extension [Package] {
    /// Sorts a filtered inventory without mutating its source. Descriptors are
    /// honored in order; package identity is always the final ascending
    /// tie-break, even when the final visible column is descending.
    func sortedForTable(
        using descriptors: [PackageTableSortDescriptor],
        pinnedFirst pinnedIDs: Set<String> = []
    ) -> [Package] {
        let descriptors = PackageTableSortDescriptor.validated(descriptors)
        let sorted = sorted { lhs, rhs in
            for descriptor in descriptors {
                switch descriptor.compare(lhs, rhs) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    continue
                }
            }
            return lhs.id < rhs.id
        }
        guard !pinnedIDs.isEmpty else { return sorted }
        return sorted.filter { pinnedIDs.contains($0.id) }
            + sorted.filter { !pinnedIDs.contains($0.id) }
    }
}

/// Key-agnostic UserDefaults seam for the inventory presentation preferences.
/// Keeping the keys at the coordinator boundary lets this helper round-trip only
/// APP-F3 state and guarantees the existing List sort preference is untouched.
struct InventoryPresentationPreferences: Equatable, Sendable {
    var viewMode: InventoryViewMode
    var tableSortOrder: [PackageTableSortDescriptor]

    init(
        viewMode: InventoryViewMode = .list,
        tableSortOrder: [PackageTableSortDescriptor] = PackageTableSortDescriptor.defaultOrder
    ) {
        self.viewMode = viewMode
        self.tableSortOrder = PackageTableSortDescriptor.validated(tableSortOrder)
    }

    static func restore(
        from defaults: UserDefaults,
        viewModeKey: String,
        tableSortOrderKey: String
    ) -> InventoryPresentationPreferences {
        let viewMode = defaults.string(forKey: viewModeKey)
            .flatMap(InventoryViewMode.init(rawValue:)) ?? .list

        let tableSortOrder: [PackageTableSortDescriptor]
        if let data = defaults.data(forKey: tableSortOrderKey),
           let decoded = try? JSONDecoder().decode(
               [PackageTableSortDescriptor].self,
               from: data
           ) {
            tableSortOrder = PackageTableSortDescriptor.validated(decoded)
        } else {
            tableSortOrder = PackageTableSortDescriptor.defaultOrder
        }

        return InventoryPresentationPreferences(
            viewMode: viewMode,
            tableSortOrder: tableSortOrder
        )
    }

    func persist(
        to defaults: UserDefaults,
        viewModeKey: String,
        tableSortOrderKey: String
    ) {
        defaults.set(viewMode.rawValue, forKey: viewModeKey)
        let validatedOrder = PackageTableSortDescriptor.validated(tableSortOrder)
        if let data = try? JSONEncoder().encode(validatedOrder) {
            defaults.set(data, forKey: tableSortOrderKey)
        }
    }
}
