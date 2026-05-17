import Testing
import Foundation
@testable import InstalloryCore

@Suite("SnapshotDiff")
struct SnapshotDiffTests {

    // MARK: - Helpers

    private func makeSnapshot(
        brew: [String] = [],
        pip: [String: [String]] = [:],   // qualifier → names
        npm: [String] = [],
        pipx: [String] = [],
        cargo: [String] = [],
        gem: [String] = [],
        mas: [String] = [],
        version: String = "1.0.0"
    ) -> Snapshot {
        var managers: [PackageManager: [SnapshotPackage]] = [:]
        if !brew.isEmpty {
            managers[.brew] = brew.map { SnapshotPackage(name: $0, version: version, qualifier: nil, isExplicit: true) }
        }
        for (qualifier, names) in pip {
            managers[.pip] = (managers[.pip] ?? []) + names.map {
                SnapshotPackage(name: $0, version: version, qualifier: qualifier.isEmpty ? nil : qualifier, isExplicit: true)
            }
        }
        if !npm.isEmpty {
            managers[.npm] = npm.map { SnapshotPackage(name: $0, version: version, qualifier: nil, isExplicit: true) }
        }
        if !pipx.isEmpty {
            managers[.pipx] = pipx.map { SnapshotPackage(name: $0, version: version, qualifier: nil, isExplicit: true) }
        }
        if !cargo.isEmpty {
            managers[.cargo] = cargo.map { SnapshotPackage(name: $0, version: version, qualifier: nil, isExplicit: true) }
        }
        if !gem.isEmpty {
            managers[.gem] = gem.map { SnapshotPackage(name: $0, version: version, qualifier: nil, isExplicit: true) }
        }
        if !mas.isEmpty {
            managers[.mas] = mas.map { SnapshotPackage(name: $0, version: version, qualifier: nil, isExplicit: true) }
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
            id: "\(manager.rawValue):\(qualifier ?? ""):\(name)",
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

    // MARK: - Empty / trivial cases

    @Test func emptySnapshotProducesEmptyDiff() {
        let snapshot = makeSnapshot()
        let result = snapshotDiff(snapshot: snapshot, livePackages: [])
        #expect(result.isEmpty)
    }

    @Test func emptyLiveInventoryReturnsAllSnapshotPackages() {
        let snapshot = makeSnapshot(brew: ["ffmpeg", "git"])
        let result = snapshotDiff(snapshot: snapshot, livePackages: [])
        #expect(result.count == 2)
        let names = Set(result.map(\.package.name))
        #expect(names == ["ffmpeg", "git"])
    }

    @Test func fullMatchProducesEmptyDiff() {
        let snapshot = makeSnapshot(brew: ["ffmpeg", "git"])
        let live = [
            makePackage(manager: .brew, name: "ffmpeg"),
            makePackage(manager: .brew, name: "git"),
        ]
        let result = snapshotDiff(snapshot: snapshot, livePackages: live)
        #expect(result.isEmpty)
    }

    // MARK: - Partial match

    @Test func partialMatchReturnsOnlyMissingPackages() {
        let snapshot = makeSnapshot(brew: ["ffmpeg", "git", "wget"])
        let live = [makePackage(manager: .brew, name: "git")]
        let result = snapshotDiff(snapshot: snapshot, livePackages: live)
        #expect(result.count == 2)
        let names = Set(result.map(\.package.name))
        #expect(names == ["ffmpeg", "wget"])
    }

    // MARK: - Version is ignored in matching

    @Test func differentVersionIsStillConsideredPresent() {
        let snapshot = makeSnapshot(brew: ["ffmpeg"], version: "7.0.0")
        let live = [makePackage(manager: .brew, name: "ffmpeg", version: "7.1.0")]
        let result = snapshotDiff(snapshot: snapshot, livePackages: live)
        #expect(result.isEmpty, "A newer installed version means the package IS present — not missing")
    }

    // MARK: - Manager identity

    @Test func sameNameDifferentManagerIsNotAMatch() {
        let snapshot = makeSnapshot(brew: ["node"])
        let live = [makePackage(manager: .npm, name: "node")]
        let result = snapshotDiff(snapshot: snapshot, livePackages: live)
        #expect(result.count == 1)
        #expect(result.first?.manager == .brew)
    }

    @Test func managerIsPreservedOnMissingPackage() {
        let snapshot = makeSnapshot(pip: ["": ["requests"]])
        let result = snapshotDiff(snapshot: snapshot, livePackages: [])
        #expect(result.first?.manager == .pip)
    }

    // MARK: - Qualifier-sensitive pip matching

    @Test func pipWithDifferentQualifiersAreDifferentPackages() {
        let snap = makeSnapshot(pip: [
            "/usr/bin/python3": ["requests"],
            "/opt/homebrew/bin/python3.13": ["requests"],
        ])
        // Only the system interpreter's "requests" is installed live
        let live = [makePackage(manager: .pip, name: "requests", qualifier: "/usr/bin/python3")]
        let result = snapshotDiff(snapshot: snap, livePackages: live)
        #expect(result.count == 1, "The brew-interpreter requests is missing; system one is present")
        #expect(result.first?.package.qualifier == "/opt/homebrew/bin/python3.13")
    }

    @Test func pipNilQualifierMatchesNilQualifier() {
        let snap = makeSnapshot(pip: ["": ["pip"]])
        let live = [makePackage(manager: .pip, name: "pip", qualifier: nil)]
        let result = snapshotDiff(snapshot: snap, livePackages: live)
        #expect(result.isEmpty)
    }

    @Test func pipNilQualifierDoesNotMatchNonNilQualifier() {
        let snap = makeSnapshot(pip: ["": ["pip"]])
        let live = [makePackage(manager: .pip, name: "pip", qualifier: "/opt/homebrew/bin/python3")]
        let result = snapshotDiff(snapshot: snap, livePackages: live)
        #expect(result.count == 1, "nil-qualifier snapshot entry doesn't match a qualified live package")
    }

    // MARK: - Multiple managers in one snapshot

    @Test func multipleManagersDiffedCorrectly() {
        let snap = makeSnapshot(brew: ["ffmpeg"], npm: ["typescript"])
        let live = [makePackage(manager: .brew, name: "ffmpeg")]
        let result = snapshotDiff(snapshot: snap, livePackages: live)
        #expect(result.count == 1)
        #expect(result.first?.manager == .npm)
        #expect(result.first?.package.name == "typescript")
    }

    // MARK: - MissingPackage identity

    @Test func missingPackageIDIsStableAndUnique() {
        let snap = makeSnapshot(brew: ["ffmpeg", "git"])
        let result = snapshotDiff(snapshot: snap, livePackages: [])
        let ids = result.map(\.id)
        #expect(Set(ids).count == ids.count, "IDs must be unique")
        for mp in result {
            let expected = "\(mp.manager.rawValue):\(mp.package.qualifier ?? ""):\(mp.package.name)"
            #expect(mp.id == expected)
        }
    }
}
