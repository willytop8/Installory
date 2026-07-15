import Testing
import Foundation
@testable import InstalloryCore

@Suite("SnapshotChanges")
struct SnapshotChangesTests {

    // MARK: - Helpers (mirrors SnapshotDiffTests)

    private func makeSnapshot(
        brew: [(name: String, version: String)] = [],
        pip: [(qualifier: String, name: String, version: String)] = [],
        npm: [(name: String, version: String)] = [],
        cargo: [(name: String, version: String)] = [],
        gem: [(qualifier: String, name: String, version: String)] = []
    ) -> Snapshot {
        var managers: [PackageManager: [SnapshotPackage]] = [:]
        if !brew.isEmpty {
            managers[.brew] = brew.map {
                SnapshotPackage(name: $0.name, version: $0.version, qualifier: nil, isExplicit: true)
            }
        }
        if !npm.isEmpty {
            managers[.npm] = npm.map {
                SnapshotPackage(name: $0.name, version: $0.version, qualifier: nil, isExplicit: true)
            }
        }
        if !cargo.isEmpty {
            managers[.cargo] = cargo.map {
                SnapshotPackage(name: $0.name, version: $0.version, qualifier: nil, isExplicit: true)
            }
        }
        for entry in pip {
            let q: String? = entry.qualifier.isEmpty ? nil : entry.qualifier
            managers[.pip, default: []].append(
                SnapshotPackage(name: entry.name, version: entry.version, qualifier: q, isExplicit: true)
            )
        }
        for entry in gem {
            let q: String? = entry.qualifier.isEmpty ? nil : entry.qualifier
            managers[.gem, default: []].append(
                SnapshotPackage(name: entry.name, version: entry.version, qualifier: q, isExplicit: true)
            )
        }
        return Snapshot(
            id: UUID(),
            createdAt: Date(),
            reason: .manual,
            note: nil,
            payload: SnapshotPayload(managers: managers)
        )
    }

    private func makePackage(
        manager: PackageManager,
        name: String,
        qualifier: String? = nil,
        version: String = "1.0.0"
    ) -> Package {
        Package(
            id: manager == .gem
                ? "\(manager.rawValue):\(qualifier ?? ""):\(name):\(version)"
                : "\(manager.rawValue):\(qualifier ?? ""):\(name)",
            manager: manager,
            qualifier: qualifier,
            name: name,
            version: version,
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date()
        )
    }

    // MARK: - Added

    @Test func packageInLiveButNotSnapshotIsAdded() {
        let snapshot = makeSnapshot(brew: [("wget", "1.0.0")])
        let live = [
            makePackage(manager: .brew, name: "wget"),
            makePackage(manager: .brew, name: "ripgrep"),  // new
        ]
        let result = snapshotChanges(from: snapshot, to: live)
        #expect(result.added.count == 1)
        #expect(result.added.first?.name == "ripgrep")
        #expect(result.removed.isEmpty)
        #expect(result.versionChanged.isEmpty)
    }

    @Test func emptySnapshotMakesAllLivePackagesAdded() {
        let snapshot = makeSnapshot()
        let live = [
            makePackage(manager: .brew, name: "wget"),
            makePackage(manager: .npm, name: "typescript"),
        ]
        let result = snapshotChanges(from: snapshot, to: live)
        #expect(result.added.count == 2)
        #expect(result.removed.isEmpty)
        #expect(result.versionChanged.isEmpty)
    }

    // MARK: - Removed

    @Test func packageInSnapshotButNotLiveIsRemoved() {
        let snapshot = makeSnapshot(brew: [("wget", "1.0.0"), ("jq", "1.7.0")])
        let live = [makePackage(manager: .brew, name: "wget")]
        let result = snapshotChanges(from: snapshot, to: live)
        #expect(result.removed.count == 1)
        #expect(result.removed.first?.package.name == "jq")
        #expect(result.added.isEmpty)
        #expect(result.versionChanged.isEmpty)
    }

    @Test func removedPackageParityWithSnapshotDiff() {
        // snapshotChanges.removed must match snapshotDiff for the same inputs
        let snapshot = makeSnapshot(brew: [("ffmpeg", "6.1.1"), ("wget", "1.0.0")])
        let live = [makePackage(manager: .brew, name: "wget")]
        let diffResult = snapshotDiff(snapshot: snapshot, livePackages: live)
        let changesResult = snapshotChanges(from: snapshot, to: live)
        #expect(diffResult.count == changesResult.removed.count)
        let diffNames = Set(diffResult.map(\.package.name))
        let changesNames = Set(changesResult.removed.map(\.package.name))
        #expect(diffNames == changesNames)
    }

    // MARK: - VersionChanged

    @Test func sameIdentityDifferentVersionIsVersionChanged() {
        let snapshot = makeSnapshot(brew: [("ffmpeg", "6.0.0")])
        let live = [makePackage(manager: .brew, name: "ffmpeg", version: "6.1.1")]
        let result = snapshotChanges(from: snapshot, to: live)
        #expect(result.versionChanged.count == 1)
        let vc = result.versionChanged[0]
        #expect(vc.name == "ffmpeg")
        #expect(vc.oldVersion == "6.0.0")
        #expect(vc.newVersion == "6.1.1")
        #expect(result.added.isEmpty)
        #expect(result.removed.isEmpty)
    }

    @Test func versionChangedPackageNotAlsoInAddedOrRemoved() {
        // A package with a different version must appear ONLY in versionChanged.
        let snapshot = makeSnapshot(
            brew: [("ffmpeg", "6.0.0"), ("wget", "1.0.0")]
        )
        let live = [
            makePackage(manager: .brew, name: "ffmpeg", version: "6.1.1"),
            makePackage(manager: .brew, name: "wget", version: "1.0.0"),
            makePackage(manager: .brew, name: "ripgrep", version: "14.0.0"),  // added
        ]
        let result = snapshotChanges(from: snapshot, to: live)
        #expect(result.versionChanged.count == 1)
        #expect(result.versionChanged.first?.name == "ffmpeg")
        #expect(result.added.count == 1)
        #expect(result.added.first?.name == "ripgrep")
        #expect(result.removed.isEmpty)
        // ffmpeg must not appear in added
        #expect(!result.added.contains { $0.name == "ffmpeg" })
    }

    @Test("CORE25-007: coexisting gem versions remain distinct in snapshot changes")
    func coexistingGemVersionsRemainDistinct() throws {
        let qualifier = "/Users/tester/.gem/ruby/3.3.0/specifications"
        let snapshot = makeSnapshot(gem: [
            (qualifier, "nokogiri", "1.15.4"),
            (qualifier, "nokogiri", "1.16.8"),
        ])
        let live = [
            makePackage(
                manager: .gem,
                name: "nokogiri",
                qualifier: qualifier,
                version: "1.16.8"
            ),
            makePackage(
                manager: .gem,
                name: "nokogiri",
                qualifier: qualifier,
                version: "1.17.0"
            ),
        ]

        let changes = snapshotChanges(from: snapshot, to: live)
        #expect(changes.added.map(\.version) == ["1.17.0"])
        #expect(changes.removed.map(\.package.version) == ["1.15.4"])
        #expect(changes.versionChanged.isEmpty)
        #expect(snapshotDiff(snapshot: snapshot, livePackages: live).map(\.package.version) == ["1.15.4"])

        let old = try #require(snapshot.payload.managers[.gem]?.first)
        let newer = try #require(snapshot.payload.managers[.gem]?.last)
        #expect(old.id != newer.id)
        #expect(MissingPackage(manager: .gem, package: old).id
            != MissingPackage(manager: .gem, package: newer).id)
    }

    // MARK: - Identical inventories

    @Test func identicalInventoriesProducesEmptyChangeSet() {
        let snapshot = makeSnapshot(brew: [("ffmpeg", "6.1.1"), ("wget", "1.0.0")])
        let live = [
            makePackage(manager: .brew, name: "ffmpeg", version: "6.1.1"),
            makePackage(manager: .brew, name: "wget", version: "1.0.0"),
        ]
        let result = snapshotChanges(from: snapshot, to: live)
        #expect(result.isEmpty)
    }

    @Test func emptySnapshotAndEmptyLiveIsEmpty() {
        let result = snapshotChanges(from: makeSnapshot(), to: [])
        #expect(result.isEmpty)
    }

    // MARK: - Qualifier-sensitive matching

    @Test func pipDifferentQualifiersAreIndependent() {
        let snapshot = makeSnapshot(pip: [
            (qualifier: "/usr/bin/python3", name: "requests", version: "2.28.0"),
        ])
        let live = [
            makePackage(manager: .pip, name: "requests", qualifier: "/opt/homebrew/bin/python3", version: "2.31.0"),
        ]
        let result = snapshotChanges(from: snapshot, to: live)
        // The brew-python requests is "added"; the system-python requests is "removed"
        #expect(result.added.count == 1)
        #expect(result.added.first?.qualifier == "/opt/homebrew/bin/python3")
        #expect(result.removed.count == 1)
        #expect(result.removed.first?.package.qualifier == "/usr/bin/python3")
        #expect(result.versionChanged.isEmpty)
    }

    // MARK: - Regression guard: existing snapshotDiff unchanged

    @Test func existingSnapshotDiffFunctionUnchanged() {
        // Verifies the recovery-direction function still works as before.
        let snapshot = makeSnapshot(brew: [("ffmpeg", "6.1.1"), ("wget", "1.0.0")])
        let live = [makePackage(manager: .brew, name: "wget", version: "1.0.0")]
        let result = snapshotDiff(snapshot: snapshot, livePackages: live)
        #expect(result.count == 1)
        #expect(result.first?.package.name == "ffmpeg")
    }

    // MARK: - Determinism

    @Test func deterministicResultForSameInput() {
        let snapshot = makeSnapshot(
            brew: [("ffmpeg", "6.0.0"), ("jq", "1.7.0")],
            npm: [("typescript", "5.0.0")]
        )
        let live = [
            makePackage(manager: .brew, name: "ffmpeg", version: "6.1.1"),
            makePackage(manager: .npm, name: "typescript", version: "5.0.0"),
            makePackage(manager: .brew, name: "ripgrep", version: "14.0.0"),
        ]
        let r1 = snapshotChanges(from: snapshot, to: live)
        let r2 = snapshotChanges(from: snapshot, to: live)
        #expect(r1.added.count == r2.added.count)
        #expect(r1.removed.count == r2.removed.count)
        #expect(r1.versionChanged.count == r2.versionChanged.count)
    }

    @Test("CORE25-015: change arrays use stable identity order")
    func changeArraysUseStableIdentityOrder() {
        let snapshot = makeSnapshot(brew: [
            ("zulu-removed", "1"),
            ("delta-changed", "1"),
            ("whiskey-removed", "1"),
            ("charlie-changed", "1"),
            ("victor-removed", "1"),
            ("bravo-changed", "1"),
            ("uniform-removed", "1"),
            ("alpha-changed", "1"),
        ])
        let live = [
            makePackage(manager: .brew, name: "hotel-added"),
            makePackage(manager: .brew, name: "delta-changed", version: "2"),
            makePackage(manager: .brew, name: "golf-added"),
            makePackage(manager: .brew, name: "charlie-changed", version: "2"),
            makePackage(manager: .brew, name: "foxtrot-added"),
            makePackage(manager: .brew, name: "bravo-changed", version: "2"),
            makePackage(manager: .brew, name: "echo-added"),
            makePackage(manager: .brew, name: "alpha-changed", version: "2"),
        ]

        let result = snapshotChanges(from: snapshot, to: live)

        #expect(result.added.map(\.name) == [
            "echo-added", "foxtrot-added", "golf-added", "hotel-added",
        ])
        #expect(result.removed.map(\.package.name) == [
            "uniform-removed", "victor-removed", "whiskey-removed", "zulu-removed",
        ])
        #expect(result.versionChanged.map(\.name) == [
            "alpha-changed", "bravo-changed", "charlie-changed", "delta-changed",
        ])
        #expect(snapshotDiff(snapshot: snapshot, livePackages: live).map(\.package.name) == [
            "uniform-removed", "victor-removed", "whiskey-removed", "zulu-removed",
        ])
    }

    // MARK: - VersionChange identity

    @Test func versionChangeIDIsStable() {
        let snapshot = makeSnapshot(brew: [("ffmpeg", "6.0.0")])
        let live = [makePackage(manager: .brew, name: "ffmpeg", version: "6.1.1")]
        let result = snapshotChanges(from: snapshot, to: live)
        let vc = result.versionChanged[0]
        #expect(vc.id == "brew::ffmpeg")
    }
}
