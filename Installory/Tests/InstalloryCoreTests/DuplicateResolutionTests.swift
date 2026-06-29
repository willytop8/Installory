import InstalloryCore
import Foundation
import Testing

// MARK: - Helpers

private let ref = Date(timeIntervalSince1970: 1_710_000_000)

/// Build a test Package. `qualifier` comes before `installPath` to match the
/// function signature order.
private func pkg(
    _ name: String,
    manager: PackageManager,
    qualifier: String? = nil,
    installPath: String? = nil
) -> Package {
    let id = qualifier.map { "\(manager.rawValue):\($0):\(name)" }
        ?? "\(manager.rawValue)::\(name)"
    return Package(
        id: id,
        manager: manager,
        qualifier: qualifier,
        name: name,
        version: "1.0.0",
        installPath: installPath.map { URL(fileURLWithPath: $0) },
        installedAt: ref,
        installedAtConfidence: .low,
        sizeBytes: nil,
        isExplicit: true,
        isReadOnly: false,
        dependencies: [],
        lastSeen: ref
    )
}

// Convenience: compare optional PathStanding without type annotation noise.
private func standing(_ s: PathStanding) -> PathStanding? { .some(s) }

// MARK: - PATH resolution tests

@Suite("PATH resolution — resolvePathStandings")
struct PathResolutionTests {

    // Canonical install paths that match the documented layout assumptions.
    // (qualifier: must come before installPath: in the call)
    private let brewNode = pkg("node", manager: .brew,
                               installPath: "/opt/homebrew/Cellar/node/20.0.0")
    private let cargoNode = pkg("node", manager: .cargo,
                                installPath: "/Users/x/.cargo/bin/node")
    private let npmNode = pkg("node", manager: .npm,
                              installPath: "/opt/homebrew/lib/node_modules/node")
    private let pipxBlack = pkg("black", manager: .pipx,
                                installPath: "/Users/x/.local/pipx/venvs/black")
    private let gemBundler = pkg("bundler", manager: .gem,
                                 installPath: "/Users/x/.rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/gems/bundler-2.5.9")
    private let pipRequests = pkg("requests", manager: .pip,
                                  qualifier: "/opt/homebrew/bin/python3",
                                  installPath: "/opt/homebrew/lib/python3.12/site-packages/requests")
    private let masXcode = pkg("Xcode", manager: .mas,
                               qualifier: "com.apple.dt.Xcode",
                               installPath: "/Applications/Xcode.app")

    // MARK: Spec 01 – winner is earliest PATH entry

    @Test("Winner is the package on the earliest PATH entry")
    func winnerIsEarliestPathEntry() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let path = ["/opt/homebrew/bin", "/Users/x/.cargo/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        #expect(standings[brewNode.id] == standing(.wins))
        #expect(standings[cargoNode.id] == standing(.shadowed(byPackageId: brewNode.id)))
    }

    @Test("Reordering PATH flips the winner")
    func reorderingPathFlipsWinner() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let path = ["/Users/x/.cargo/bin", "/opt/homebrew/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        #expect(standings[cargoNode.id] == standing(.wins))
        #expect(standings[brewNode.id] == standing(.shadowed(byPackageId: cargoNode.id)))
    }

    @Test("Package whose dir is absent from PATH is unknown, not shadowed")
    func packageAbsentFromPathIsUnknown() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        // Only brew bin on PATH; cargo bin absent.
        let path = ["/opt/homebrew/bin", "/usr/bin", "/usr/local/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        #expect(standings[brewNode.id] == standing(.wins))
        #expect(standings[cargoNode.id] == standing(.unknown))
    }

    @Test("No PATH match for any member → no winner, all unknown, no crash")
    func noPathMatchForAnyMember() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let path = ["/usr/bin"]  // neither brew nor cargo present
        let standings = resolvePathStandings(for: group, path: path)

        #expect(standings[brewNode.id] == standing(.unknown))
        #expect(standings[cargoNode.id] == standing(.unknown))
    }

    @Test("Empty PATH string → all packages unknown")
    func emptyPathAllUnknown() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let standings = resolvePathStandings(for: group, path: [])

        #expect(standings.values.allSatisfy { $0 == .unknown })
        #expect(standings.count == 2)
    }

    @Test("Resolution is deterministic: calling twice with same inputs yields same output")
    func resolutionIsDeterministic() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let path = ["/opt/homebrew/bin", "/Users/x/.cargo/bin"]

        let r1 = resolvePathStandings(for: group, path: path)
        let r2 = resolvePathStandings(for: group, path: path)

        #expect(r1[brewNode.id] == r2[brewNode.id])
        #expect(r1[cargoNode.id] == r2[cargoNode.id])
    }

    @Test("Resolution does not mutate input packages")
    func resolutionDoesNotMutateInput() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let path = ["/opt/homebrew/bin", "/Users/x/.cargo/bin"]
        _ = resolvePathStandings(for: group, path: path)

        // Package values are structs; verify ids haven't changed
        #expect(group.packages[0].id == brewNode.id)
        #expect(group.packages[1].id == cargoNode.id)
    }

    @Test("Tie at earliest PATH index → no winner declared, all tied packages unknown")
    func tieAtEarliestIndexNoWinner() {
        // brew and npm both route to /opt/homebrew/bin — tie at index 0.
        let group = DuplicateGroup(name: "node", packages: [brewNode, npmNode])
        let path = ["/opt/homebrew/bin", "/usr/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        // Neither can be declared winner when both land on the same dir.
        #expect(standings[brewNode.id] == standing(.unknown))
        #expect(standings[npmNode.id] == standing(.unknown))
    }

    @Test("pip and mas packages (no executable dir) → always unknown")
    func pipAndMasAlwaysUnknown() {
        let group = DuplicateGroup(name: "requests", packages: [pipRequests, masXcode])
        let path = ["/opt/homebrew/bin", "/usr/bin", "/usr/local/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        #expect(standings[pipRequests.id] == standing(.unknown))
        #expect(standings[masXcode.id] == standing(.unknown))
    }

    @Test("All result keys are in the group's package ids")
    func resultKeysMatchGroupPackageIds() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode, npmNode])
        let path = ["/opt/homebrew/bin", "/Users/x/.cargo/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        let expectedIds = Set(group.packages.map(\.id))
        #expect(Set(standings.keys) == expectedIds)
    }

    @Test("pipx executable directory derivation works")
    func pipxExecutableDirectoryDerived() {
        // pipx venv at ~/.local/pipx/venvs/black → executable at ~/.local/bin
        let group = DuplicateGroup(name: "black",
                                   packages: [pipxBlack,
                                              pkg("black", manager: .brew,
                                                  installPath: "/opt/homebrew/Cellar/black/24.0")])
        let path = ["/Users/x/.local/bin", "/opt/homebrew/bin"]
        let standings = resolvePathStandings(for: group, path: path)
        #expect(standings[pipxBlack.id] == standing(.wins))
    }

    @Test("gem executable directory derivation works")
    func gemExecutableDirectoryDerived() {
        // gem at rbenv-version/lib/ruby/gems/3.2.0/gems/bundler-2.5.9 → bin at rbenv-version/bin
        let group = DuplicateGroup(name: "bundler",
                                   packages: [gemBundler,
                                              pkg("bundler", manager: .brew,
                                                  installPath: "/opt/homebrew/Cellar/bundler/2.5")])
        let path = ["/Users/x/.rbenv/versions/3.2.2/bin", "/opt/homebrew/bin"]
        let standings = resolvePathStandings(for: group, path: path)
        #expect(standings[gemBundler.id] == standing(.wins))
    }
}

// MARK: - Severity tests

@Suite("Duplicate severity — severity(for:standings:)")
struct DuplicateSeverityTests {

    private let brewNode = pkg("node", manager: .brew,
                               installPath: "/opt/homebrew/Cellar/node/20.0.0")
    private let cargoNode = pkg("node", manager: .cargo,
                                installPath: "/Users/x/.cargo/bin/node")
    private let pipRequests = pkg("requests", manager: .pip,
                                  qualifier: "/opt/homebrew/bin/python3",
                                  installPath: "/opt/homebrew/lib/python3.12/site-packages/requests")
    private let masXcode = pkg("Xcode", manager: .mas,
                               qualifier: "com.apple.dt.Xcode",
                               installPath: "/Applications/Xcode.app")

    @Test("Active: real PATH shadow exists → .active")
    func activeSeverityForRealShadow() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let path = ["/opt/homebrew/bin", "/Users/x/.cargo/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        #expect(severity(for: group, standings: standings) == .active)
    }

    @Test("Potential: CLI-ish cross-manager duplicate, PATH fully unresolved → .potential")
    func potentialSeverityForUnresolvedPath() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        // PATH that matches neither brew nor cargo bin.
        let standings = resolvePathStandings(for: group, path: ["/usr/bin"])
        #expect(severity(for: group, standings: standings) == .potential)
    }

    @Test("Benign: winner exists but no shadow → nothing actively conflicting")
    func benignSeverityWinnerButNoShadow() {
        // brew node on PATH, pip node NOT on PATH (pip has no executable dir).
        let group = DuplicateGroup(name: "node", packages: [brewNode, pipRequests])
        let path = ["/opt/homebrew/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        #expect(standings[brewNode.id] == standing(.wins))
        #expect(standings[pipRequests.id] == standing(.unknown))
        #expect(severity(for: group, standings: standings) == .benign)
    }

    @Test("Benign: all packages are app bundles/non-CLI → library name collision")
    func benignSeverityForNonCliPackages() {
        // pip and mas both have nil executable dirs — no CLI signal.
        let group = DuplicateGroup(name: "Xcode", packages: [pipRequests, masXcode])
        let standings = resolvePathStandings(for: group, path: [])
        #expect(severity(for: group, standings: standings) == .benign)
    }

    @Test("Severity ordering: active > potential > benign")
    func severityOrdering() {
        #expect(DuplicateSeverity.active > DuplicateSeverity.potential)
        #expect(DuplicateSeverity.potential > DuplicateSeverity.benign)
        #expect(DuplicateSeverity.active > DuplicateSeverity.benign)
    }

    @Test("Severity is deterministic across multiple calls")
    func severityIsDeterministic() {
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let path = ["/opt/homebrew/bin", "/Users/x/.cargo/bin"]
        let standings = resolvePathStandings(for: group, path: path)

        let s1 = severity(for: group, standings: standings)
        let s2 = severity(for: group, standings: standings)
        #expect(s1 == s2)
    }

    @Test("Severity never modifies the group's packages")
    func severityDoesNotMutateInput() {
        let originalName = brewNode.name
        let group = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let standings = resolvePathStandings(for: group, path: ["/opt/homebrew/bin"])
        _ = severity(for: group, standings: standings)
        #expect(group.packages.first?.name == originalName)
    }

    @Test("Active groups sort before potential, potential before benign")
    func sortedBySeverityPutsActiveFirst() {
        let activeGroup = DuplicateGroup(name: "node", packages: [brewNode, cargoNode])
        let potentialGroup = DuplicateGroup(
            name: "tool",
            packages: [
                pkg("tool", manager: .brew, installPath: "/opt/homebrew/Cellar/tool/1.0"),
                pkg("tool", manager: .npm, installPath: "/opt/homebrew/lib/node_modules/tool"),
            ]
        )

        let path = ["/opt/homebrew/bin", "/Users/x/.cargo/bin"]
        let activeStandings = resolvePathStandings(for: activeGroup, path: path)
        // potentialGroup: PATH /usr/bin matches neither brew nor npm bin → all unknown
        // Both packages are CLI-ish → .potential
        let potentialStandings = resolvePathStandings(for: potentialGroup, path: ["/usr/bin"])

        let activeSev = severity(for: activeGroup, standings: activeStandings)
        let potentialSev = severity(for: potentialGroup, standings: potentialStandings)

        #expect(activeSev == .active)
        #expect(potentialSev == .potential)
        #expect(activeSev > potentialSev)

        // Verify sort order using named standings lookup.
        struct Pair { let group: DuplicateGroup; let standings: [String: PathStanding] }
        let pairs: [Pair] = [
            Pair(group: potentialGroup, standings: potentialStandings),
            Pair(group: activeGroup, standings: activeStandings),
        ]
        let sorted = pairs.sorted {
            severity(for: $0.group, standings: $0.standings)
            >
            severity(for: $1.group, standings: $1.standings)
        }
        #expect(sorted[0].group.name == "node")  // active first
        #expect(sorted[1].group.name == "tool")  // potential second
    }
}
