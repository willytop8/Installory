import InstalloryCore
import Foundation
import Testing

@Suite("Free-up-space bundle")
struct FreeUpSpaceTests {

    private static let ref = Date(timeIntervalSince1970: 1_710_000_000)

    private func pkg(
        _ name: String,
        manager: PackageManager = .brew,
        qualifier: String? = nil,
        deps: [String] = [],
        isExplicit: Bool = true,
        isReadOnly: Bool = false,
        sizeBytes: Int64? = 1_000_000
    ) -> Package {
        let id = "\(manager.rawValue):\(qualifier ?? ""):\(name)"
        return Package(
            id: id,
            manager: manager,
            qualifier: qualifier,
            name: name,
            version: "1.0.0",
            installPath: nil,
            installedAt: Self.ref,
            installedAtConfidence: .high,
            sizeBytes: sizeBytes,
            isExplicit: isExplicit,
            isReadOnly: isReadOnly,
            dependencies: deps,
            artifactPaths: nil,
            lastSeen: Self.ref
        )
    }

    private func bundle(for packages: [Package], limit: Int = 5) -> FreeUpSpaceBundle {
        FreeUpSpace.bundle(
            packages: packages,
            now: Self.ref,
            reverseDependencyIndex: ReverseDependencyIndex(packages: packages),
            limit: limit
        )
    }

    @Test("Empty inventory produces an empty bundle")
    func emptyInventory() {
        let result = bundle(for: [])
        #expect(result.isEmpty)
        #expect(result.candidates.isEmpty)
        #expect(result.totalReclaimableBytes == 0)
    }

    @Test("Denylisted packages are excluded")
    func denylistedExcluded() {
        let result = bundle(for: [pkg("git")])
        #expect(result.isEmpty)
    }

    @Test("Packages with dependents are excluded")
    func dependentsExcluded() {
        let lib = pkg("mylib")
        let app = pkg("myapp", deps: ["mylib"])
        let result = bundle(for: [lib, app])
        #expect(result.candidates.count == 1)
        #expect(result.candidates[0].package.name == "myapp")
    }

    @Test("Read-only packages are excluded")
    func readOnlyExcluded() {
        let result = bundle(for: [pkg("system-tool", isReadOnly: true)])
        #expect(result.isEmpty)
    }

    @Test("Packages with unknown or zero size are excluded")
    func zeroSizeExcluded() {
        let zero = pkg("empty-tool", sizeBytes: nil)
        let alsoZero = pkg("other-tool", sizeBytes: 0)
        let real = pkg("real-tool", sizeBytes: 500)
        let result = bundle(for: [zero, alsoZero, real])
        #expect(result.candidates.count == 1)
        #expect(result.candidates[0].package.name == "real-tool")
    }

    @Test("Total reclaimable bytes is the sum of candidate sizes")
    func totalIsSum() {
        let a = pkg("a", sizeBytes: 100)
        let b = pkg("b", sizeBytes: 250)
        let result = bundle(for: [a, b])
        #expect(result.totalReclaimableBytes == 350)
    }

    @Test("Limit caps the candidate count")
    func limitCapsCount() {
        let packages = (0..<10).map { pkg("tool-\($0)") }
        let result = bundle(for: packages, limit: 3)
        #expect(result.candidates.count == 3)
    }
}
