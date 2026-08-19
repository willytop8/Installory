import Foundation
import Testing
@testable import InstalloryCore

@Suite("Baseline diff")
struct BaselineDiffTests {
    private let now = Date(timeIntervalSince1970: 1_771_624_907)

    private func makePackage(_ name: String, manager: PackageManager = .brew, qualifier: String? = nil, version: String = "1.0.0", isExplicit: Bool = true) -> Package {
        Package(
            id: "\(manager.rawValue):\(qualifier ?? ""):\(name)",
            manager: manager,
            qualifier: qualifier,
            name: name,
            version: version,
            installPath: nil,
            installedAt: now,
            installedAtConfidence: .medium,
            sizeBytes: nil,
            isExplicit: isExplicit,
            isReadOnly: false,
            dependencies: [],
            artifactPaths: nil,
            lastSeen: now
        )
    }

    private func makeBaseline(_ packages: [SnapshotPackage]) -> SnapshotPayload {
        SnapshotPayload(managers: Dictionary(grouping: packages, by: { _ in PackageManager.brew }))
    }

    private func snapshotPackage(_ name: String, version: String = "1.0.0", qualifier: String? = nil) -> SnapshotPackage {
        SnapshotPackage(name: name, version: version, qualifier: qualifier, isExplicit: true)
    }

    @Test("packages only on this Mac are reported as added")
    func addedPackagesAreReported() {
        let baseline = makeBaseline([snapshotPackage("wget")])
        let live = [makePackage("wget"), makePackage("ffmpeg")]
        let changes = Baseline.changes(from: baseline, to: live)
        #expect(changes.added.map(\.name) == ["ffmpeg"])
        #expect(changes.removed.isEmpty)
        #expect(changes.versionChanged.isEmpty)
        #expect(!changes.isEmpty)
    }

    @Test("packages only in the baseline are reported as removed")
    func removedPackagesAreReported() {
        let baseline = makeBaseline([snapshotPackage("wget"), snapshotPackage("ripgrep")])
        let live = [makePackage("wget")]
        let changes = Baseline.changes(from: baseline, to: live)
        #expect(changes.removed.map(\.package.name) == ["ripgrep"])
        #expect(changes.added.isEmpty)
        #expect(changes.versionChanged.isEmpty)
    }

    @Test("version differences are reported as versionChanged")
    func versionChangesAreReported() {
        let baseline = makeBaseline([snapshotPackage("ffmpeg", version: "6.0.0")])
        let live = [makePackage("ffmpeg", version: "7.0.0")]
        let changes = Baseline.changes(from: baseline, to: live)
        #expect(changes.added.isEmpty)
        #expect(changes.removed.isEmpty)
        #expect(changes.versionChanged.count == 1)
        #expect(changes.versionChanged[0].name == "ffmpeg")
        #expect(changes.versionChanged[0].oldVersion == "6.0.0")
        #expect(changes.versionChanged[0].newVersion == "7.0.0")
    }

    @Test("identical inventories produce an empty change set")
    func identicalInventoriesAreEmpty() {
        let baseline = makeBaseline([snapshotPackage("wget"), snapshotPackage("ffmpeg")])
        let live = [makePackage("wget"), makePackage("ffmpeg")]
        let changes = Baseline.changes(from: baseline, to: live)
        #expect(changes.isEmpty)
        #expect(changes.added.isEmpty)
        #expect(changes.removed.isEmpty)
        #expect(changes.versionChanged.isEmpty)
    }

    @Test("an empty baseline reports every live package as added")
    func emptyBaselineAddsEverything() {
        let baseline = makeBaseline([])
        let live = [makePackage("wget"), makePackage("ffmpeg")]
        let changes = Baseline.changes(from: baseline, to: live)
        #expect(changes.added.map(\.name).sorted() == ["ffmpeg", "wget"])
        #expect(changes.isEmpty == false)
    }

    @Test("missing() reports only baseline-only packages for reinstall")
    func missingReturnsRecoveryCandidates() {
        let baseline = makeBaseline([snapshotPackage("wget"), snapshotPackage("ripgrep")])
        let live = [makePackage("wget")]
        let missing = Baseline.missing(from: baseline, to: live)
        #expect(missing.map(\.package.name) == ["ripgrep"])
    }

    @Test("an imported baseline JSON decodes with unknown manager keys skipped")
    func unknownManagerKeysAreSkipped() throws {
        let json = #"""
        {
            "brew": [{"name": "wget", "version": "1.21.4", "isExplicit": true}],
            "not-a-manager": [{"name": "ghost", "version": "1.0.0", "isExplicit": true}]
        }
        """#
        let payload = try JSONDecoder().decode(SnapshotPayload.self, from: Data(json.utf8))
        let live = [makePackage("wget")]
        let changes = Baseline.changes(from: payload, to: live)
        #expect(changes.added.isEmpty)
        #expect(changes.removed.isEmpty)
    }
}
