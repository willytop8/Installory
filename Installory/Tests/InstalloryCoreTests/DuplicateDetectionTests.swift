import InstalloryCore
import Foundation
import Testing

@Suite("Cross-manager duplicate detection")
struct DuplicateDetectionTests {
    private static let ref = Date(timeIntervalSince1970: 1_710_000_000)

    private func pkg(
        _ name: String,
        manager: PackageManager,
        qualifier: String? = nil
    ) -> Package {
        let id = qualifier.map { "\(manager.rawValue):\($0):\(name)" }
            ?? "\(manager.rawValue)::\(name)"
        return Package(
            id: id,
            manager: manager,
            qualifier: qualifier,
            name: name,
            version: "1.0.0",
            installPath: nil,
            installedAt: Self.ref,
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Self.ref
        )
    }

    // MARK: - Tests

    @Test("brew + npm both have 'node' → one duplicate group")
    func crossManagerDuplicate() {
        let packages = [
            pkg("node", manager: .brew),
            pkg("node", manager: .npm),
            pkg("ffmpeg", manager: .brew),
        ]
        let groups = packages.crossManagerDuplicates()
        #expect(groups.count == 1)
        #expect(groups[0].name.lowercased() == "node")
        #expect(groups[0].packages.count == 2)
    }

    @Test("pip × 3 interpreters for 'requests' — one manager, no group")
    func singleManagerMultiEnvironment() {
        let packages = [
            pkg("requests", manager: .pip, qualifier: "/usr/bin/python3"),
            pkg("requests", manager: .pip, qualifier: "/opt/homebrew/bin/python3"),
            pkg("requests", manager: .pip, qualifier: "/Users/x/.pyenv/versions/3.11.7/bin/python"),
        ]
        let groups = packages.crossManagerDuplicates()
        #expect(groups.isEmpty)
    }

    @Test("brew formula + brewCask of same name — same manager, no group")
    func brewAndBrewCaskAreSameManager() {
        let packages = [
            pkg("git", manager: .brew),
            pkg("git", manager: .brewCask),
        ]
        let groups = packages.crossManagerDuplicates()
        #expect(groups.isEmpty)
    }

    @Test("matching is case-insensitive: brew 'Node' + npm 'node' → one group")
    func caseInsensitiveMatching() {
        let packages = [
            pkg("Node", manager: .brew),
            pkg("node", manager: .npm),
        ]
        let groups = packages.crossManagerDuplicates()
        #expect(groups.count == 1)
        #expect(groups[0].packages.count == 2)
    }

    @Test("empty package list → empty result")
    func emptyInput() {
        let groups = [Package]().crossManagerDuplicates()
        #expect(groups.isEmpty)
    }

    @Test("multiple duplicate groups are sorted by name")
    func sortedByName() {
        let packages = [
            pkg("zebra", manager: .brew),
            pkg("zebra", manager: .npm),
            pkg("alpha", manager: .brew),
            pkg("alpha", manager: .npm),
        ]
        let groups = packages.crossManagerDuplicates()
        #expect(groups.count == 2)
        #expect(groups[0].name.lowercased() == "alpha")
        #expect(groups[1].name.lowercased() == "zebra")
    }
}
