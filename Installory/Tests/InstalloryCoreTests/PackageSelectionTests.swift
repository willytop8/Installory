import Testing
import Foundation
@testable import InstalloryCore

@Suite("PackageSelection")
struct PackageSelectionTests {

    private func makePackage(id: String, name: String, version: String, isExplicit: Bool = true) -> Package {
        Package(
            id: id,
            manager: .brew,
            qualifier: nil,
            name: name,
            version: version,
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: isExplicit,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date()
        )
    }

    @Test("APP-02: a selection is re-resolved to the freshly scanned struct")
    func selectionIsReresolvedToFreshStruct() {
        let stale = makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "6.0")
        let fresh = makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "7.1")

        let resolved = PackageSelection.resolve(stale, in: [fresh])

        #expect(resolved?.version == "7.1")
    }

    @Test("APP-02: re-resolution picks up flag changes, not just the version")
    func selectionPicksUpFlagChanges() {
        let stale = makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "6.0", isExplicit: true)
        let fresh = makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "6.0", isExplicit: false)

        #expect(PackageSelection.resolve(stale, in: [fresh])?.isExplicit == false)
    }

    @Test("APP-02: a selection that vanished from the inventory resolves to nil")
    func vanishedSelectionResolvesToNil() {
        let removed = makePackage(id: "brew::wget", name: "wget", version: "1.24.5")
        let remaining = makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "7.1")

        #expect(PackageSelection.resolve(removed, in: [remaining]) == nil)
    }

    @Test("APP-02: no selection resolves to nil")
    func noSelectionResolvesToNil() {
        let pkg = makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "7.1")
        #expect(PackageSelection.resolve(nil, in: [pkg]) == nil)
    }

    @Test("APP-02: a selection resolves to nil against an empty inventory")
    func selectionResolvesToNilAgainstEmptyInventory() {
        let pkg = makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "7.1")
        #expect(PackageSelection.resolve(pkg, in: []) == nil)
    }

    @Test("APP-02: re-resolution matches on id, not name")
    func resolutionMatchesOnIdNotName() {
        let selection = makePackage(id: "npm:/a/lib/node_modules:typescript", name: "typescript", version: "5.4.5")
        let sameNameDifferentInstall = makePackage(
            id: "npm:/b/lib/node_modules:typescript", name: "typescript", version: "5.0.0"
        )

        #expect(PackageSelection.resolve(selection, in: [sameNameDifferentInstall]) == nil)
    }
}
