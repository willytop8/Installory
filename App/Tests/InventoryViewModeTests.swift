import Foundation
import InstalloryCore
import Testing
@testable import Installory

@Suite("Inventory table presentation", .serialized)
struct InventoryViewModeTests {
    private func package(
        id: String,
        manager: PackageManager = .brew,
        name: String = "same",
        version: String = "1.0",
        sizeBytes: Int64? = 1_024,
        installedAt: Date? = Date(timeIntervalSince1970: 1_720_000_000)
    ) -> Package {
        Package(
            id: id,
            manager: manager,
            qualifier: nil,
            name: name,
            version: version,
            installPath: URL(fileURLWithPath: "/tmp/\(id)"),
            installedAt: installedAt,
            installedAtConfidence: .high,
            sizeBytes: sizeBytes,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_720_100_000)
        )
    }

    @Test("APP-F3: every table sort uses stable package identity as its final tie-breaker")
    func everySortHasStableIdentityTieBreaker() {
        let earlier = package(id: "a-package")
        let later = package(id: "z-package")

        for column in PackageTableSortColumn.allCases {
            for direction in [PackageTableSortDirection.ascending, .descending] {
                let descriptor = PackageTableSortDescriptor(
                    column: column,
                    direction: direction
                )
                #expect(
                    [later, earlier].sortedForTable(using: [descriptor]).map(\.id)
                        == [earlier.id, later.id],
                    "Missing stable identity tie-break for \(column.rawValue) \(direction.rawValue)"
                )
            }
        }
    }

    @Test("APP-F3: unknown size sorts after known sizes in both directions")
    func unknownSizeIsAlwaysLast() {
        let small = package(id: "small", sizeBytes: 10)
        let large = package(id: "large", sizeBytes: 100)
        let unknown = package(id: "unknown", sizeBytes: nil)
        let source = [unknown, large, small]

        #expect(
            source.sortedForTable(using: [
                PackageTableSortDescriptor(column: .size, direction: .ascending),
            ]).map(\.id) == [small.id, large.id, unknown.id]
        )
        #expect(
            source.sortedForTable(using: [
                PackageTableSortDescriptor(column: .size, direction: .descending),
            ]).map(\.id) == [large.id, small.id, unknown.id]
        )
    }

    @Test("APP-F3: unknown install date sorts after known dates in both directions")
    func unknownInstallDateIsAlwaysLast() {
        let early = package(
            id: "early",
            installedAt: Date(timeIntervalSince1970: 100)
        )
        let late = package(
            id: "late",
            installedAt: Date(timeIntervalSince1970: 200)
        )
        let unknown = package(id: "unknown", installedAt: nil)
        let source = [unknown, late, early]

        #expect(
            source.sortedForTable(using: [
                PackageTableSortDescriptor(column: .installed, direction: .ascending),
            ]).map(\.id) == [early.id, late.id, unknown.id]
        )
        #expect(
            source.sortedForTable(using: [
                PackageTableSortDescriptor(column: .installed, direction: .descending),
            ]).map(\.id) == [late.id, early.id, unknown.id]
        )
    }

    @Test("APP-F3: version sorting uses localized-standard numeric ordering")
    func versionSortIsNumericAware() {
        let two = package(id: "two", version: "2.0")
        let ten = package(id: "ten", version: "10.0")

        #expect(
            [ten, two].sortedForTable(using: [
                PackageTableSortDescriptor(column: .version),
            ]).map(\.id) == [two.id, ten.id]
        )
        #expect(
            [two, ten].sortedForTable(using: [
                PackageTableSortDescriptor(column: .version, direction: .descending),
            ]).map(\.id) == [ten.id, two.id]
        )
    }

    @Test("APP-F3: descriptor priority is honored before the identity tie-breaker")
    func descriptorPriorityPrecedesIdentity() {
        let identityFirst = package(id: "a-package", name: "same", sizeBytes: 100)
        let identityLast = package(id: "z-package", name: "same", sizeBytes: 10)

        let sorted = [identityLast, identityFirst].sortedForTable(using: [
            PackageTableSortDescriptor(column: .name),
            PackageTableSortDescriptor(column: .size),
        ])

        #expect(sorted.map(\.id) == [identityLast.id, identityFirst.id])
    }

    @Test("APP-F3: List and Table mode plus validated table descriptors round-trip through UI preference persistence")
    func presentationPreferencesRoundTrip() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModeKey = "test.inventory.viewMode"
        let tableSortOrderKey = "test.inventory.tableSortOrder"
        let expected = InventoryPresentationPreferences(
            viewMode: .table,
            tableSortOrder: [
                PackageTableSortDescriptor(column: .size, direction: .descending),
                PackageTableSortDescriptor(column: .manager),
            ]
        )

        expected.persist(
            to: defaults,
            viewModeKey: viewModeKey,
            tableSortOrderKey: tableSortOrderKey
        )

        #expect(
            InventoryPresentationPreferences.restore(
                from: defaults,
                viewModeKey: viewModeKey,
                tableSortOrderKey: tableSortOrderKey
            ) == expected
        )

        let list = InventoryPresentationPreferences(viewMode: .list)
        list.persist(
            to: defaults,
            viewModeKey: viewModeKey,
            tableSortOrderKey: tableSortOrderKey
        )
        #expect(
            InventoryPresentationPreferences.restore(
                from: defaults,
                viewModeKey: viewModeKey,
                tableSortOrderKey: tableSortOrderKey
            ) == list
        )
    }

    @Test("APP-F3: invalid persisted view and sort values restore safe defaults without changing the existing list sort preference")
    func invalidPreferencesRestoreSafeDefaults() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModeKey = "test.inventory.viewMode"
        let tableSortOrderKey = "test.inventory.tableSortOrder"
        let existingListSortKey = "app.installory.ui.sortOrder"
        defaults.set("largestFirst", forKey: existingListSortKey)
        defaults.set("grid", forKey: viewModeKey)
        defaults.set(
            Data(#"[{"column":"not-a-column","direction":"sideways"}]"#.utf8),
            forKey: tableSortOrderKey
        )

        let restored = InventoryPresentationPreferences.restore(
            from: defaults,
            viewModeKey: viewModeKey,
            tableSortOrderKey: tableSortOrderKey
        )

        #expect(restored.viewMode == .list)
        #expect(restored.tableSortOrder == PackageTableSortDescriptor.defaultOrder)
        #expect(defaults.string(forKey: existingListSortKey) == "largestFirst")

        defaults.set(try JSONEncoder().encode([PackageTableSortDescriptor]()), forKey: tableSortOrderKey)
        #expect(
            InventoryPresentationPreferences.restore(
                from: defaults,
                viewModeKey: viewModeKey,
                tableSortOrderKey: tableSortOrderKey
            ).tableSortOrder == PackageTableSortDescriptor.defaultOrder
        )

        let duplicateColumns = [
            PackageTableSortDescriptor(column: .name),
            PackageTableSortDescriptor(column: .name, direction: .descending),
        ]
        defaults.set(try JSONEncoder().encode(duplicateColumns), forKey: tableSortOrderKey)
        #expect(
            InventoryPresentationPreferences.restore(
                from: defaults,
                viewModeKey: viewModeKey,
                tableSortOrderKey: tableSortOrderKey
            ).tableSortOrder == PackageTableSortDescriptor.defaultOrder
        )
        #expect(defaults.string(forKey: existingListSortKey) == "largestFirst")
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "InventoryViewModeTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
