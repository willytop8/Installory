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

// MARK: - Multi-location install detection (Spec 03)

@Suite("Multi-location install detection — multiLocationInstalls()")
struct MultiLocationInstallTests {
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

    @Test("pip × 3 interpreters for 'requests' → one multi-location group of 3")
    func pipThreeInterpreters() {
        let packages = [
            pkg("requests", manager: .pip, qualifier: "/usr/bin/python3"),
            pkg("requests", manager: .pip, qualifier: "/opt/homebrew/bin/python3"),
            pkg("requests", manager: .pip, qualifier: "/Users/x/.pyenv/versions/3.11.7/bin/python"),
        ]
        let groups = packages.multiLocationInstalls()
        #expect(groups.count == 1)
        #expect(groups[0].name.lowercased() == "requests")
        #expect(groups[0].packages.count == 3)
        #expect(groups[0].manager == .pip)
    }

    @Test("Single-qualifier package → no multi-location group")
    func singleQualifierNoGroup() {
        let packages = [
            pkg("requests", manager: .pip, qualifier: "/usr/bin/python3"),
        ]
        let groups = packages.multiLocationInstalls()
        #expect(groups.isEmpty)
    }

    @Test("Same package under a single non-nil qualifier → no group")
    func samePackageSingleQualifier() {
        // Two packages with the SAME qualifier — only 1 distinct qualifier.
        let packages = [
            pkg("requests", manager: .pip, qualifier: "/usr/bin/python3"),
            pkg("requests", manager: .pip, qualifier: "/usr/bin/python3"),
        ]
        let groups = packages.multiLocationInstalls()
        #expect(groups.isEmpty)
    }

    @Test("brew + brewCask same name → no multi-location group (excluded managers)")
    func brewAndBrewCaskExcluded() {
        let packages = [
            pkg("git", manager: .brew),
            pkg("git", manager: .brewCask),
        ]
        let groups = packages.multiLocationInstalls()
        #expect(groups.isEmpty)
    }

    @Test("mas packages with distinct bundle-ID qualifiers → no group (mas excluded)")
    func masExcluded() {
        let packages = [
            pkg("Xcode", manager: .mas, qualifier: "com.apple.dt.Xcode"),
            pkg("Xcode", manager: .mas, qualifier: "com.apple.dt.Xcode.v2"),
        ]
        let groups = packages.multiLocationInstalls()
        #expect(groups.isEmpty)
    }

    @Test("gem in two rbenv Ruby versions → one multi-location group")
    func gemTwoRubyVersions() {
        let packages = [
            pkg("bundler", manager: .gem,
                qualifier: "/Users/x/.rbenv/versions/3.2.2/lib/ruby/gems/3.2.2/specifications"),
            pkg("bundler", manager: .gem,
                qualifier: "/Users/x/.rbenv/versions/3.3.0/lib/ruby/gems/3.3.0/specifications"),
        ]
        let groups = packages.multiLocationInstalls()
        #expect(groups.count == 1)
        #expect(groups[0].name.lowercased() == "bundler")
        #expect(groups[0].manager == .gem)
    }

    @Test("Nil qualifier does not count toward distinct-qualifier threshold")
    func nilQualifierDoesNotCount() {
        // One non-nil qualifier + one nil qualifier = only 1 distinct non-nil qualifier.
        let packages = [
            pkg("requests", manager: .pip, qualifier: "/usr/bin/python3"),
            pkg("requests", manager: .pip, qualifier: nil),
        ]
        let groups = packages.multiLocationInstalls()
        #expect(groups.isEmpty)
    }

    @Test("crossManagerDuplicates() unaffected by multiLocationInstalls() (regression guard)")
    func crossManagerDuplicatesUnchanged() {
        let packages = [
            pkg("node", manager: .brew),
            pkg("node", manager: .npm),
            pkg("requests", manager: .pip, qualifier: "/usr/bin/python3"),
            pkg("requests", manager: .pip, qualifier: "/opt/homebrew/bin/python3"),
        ]
        // 'node' is cross-manager; 'requests' is same-manager with qualifiers.
        let crossGroups = packages.crossManagerDuplicates()
        #expect(crossGroups.count == 1)
        #expect(crossGroups[0].name.lowercased() == "node")

        // Multi-location should find 'requests', not 'node'.
        let multiGroups = packages.multiLocationInstalls()
        #expect(multiGroups.count == 1)
        #expect(multiGroups[0].name.lowercased() == "requests")
    }

    @Test("multiLocationInstalls() is deterministic across multiple calls")
    func multiLocationDeterministic() {
        let packages = [
            pkg("requests", manager: .pip, qualifier: "/usr/bin/python3"),
            pkg("requests", manager: .pip, qualifier: "/opt/homebrew/bin/python3"),
            pkg("black", manager: .pip, qualifier: "/usr/bin/python3"),
            pkg("black", manager: .pip, qualifier: "/opt/homebrew/bin/python3"),
        ]
        let r1 = packages.multiLocationInstalls().map(\.name)
        let r2 = packages.multiLocationInstalls().map(\.name)
        #expect(r1 == r2)
    }

    @Test("Multiple managers with multi-location installs sorted by manager then name")
    func sortedByManagerThenName() {
        let packages = [
            pkg("zebra", manager: .pip, qualifier: "/usr/bin/python3"),
            pkg("zebra", manager: .pip, qualifier: "/opt/homebrew/bin/python3"),
            pkg("alpha", manager: .gem,
                qualifier: "/Users/x/.rbenv/versions/3.2.2/lib/ruby/gems/specifications"),
            pkg("alpha", manager: .gem,
                qualifier: "/Users/x/.rbenv/versions/3.3.0/lib/ruby/gems/specifications"),
        ]
        let groups = packages.multiLocationInstalls()
        #expect(groups.count == 2)
        // gem < pip alphabetically
        #expect(groups[0].manager == .gem)
        #expect(groups[1].manager == .pip)
    }

    @Test("Empty package list → empty multi-location result")
    func emptyInput() {
        let groups = [Package]().multiLocationInstalls()
        #expect(groups.isEmpty)
    }
}
