import InstalloryCore
import Foundation
import Testing

@Suite("Reverse dependency index")
struct ReverseDependencyIndexTests {

    private static let ref = Date(timeIntervalSince1970: 1_710_000_000)

    private func pkg(
        _ name: String,
        manager: PackageManager = .brew,
        qualifier: String? = nil,
        deps: [String] = []
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
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: deps,
            lastSeen: Self.ref
        )
    }

    @Test("Direct dependents are returned for a package that others depend on")
    func directDependents() {
        let packages = [
            pkg("openssl"),
            pkg("wget", deps: ["openssl"]),
            pkg("curl", deps: ["openssl"]),
        ]
        let index = ReverseDependencyIndex(packages: packages)
        let openssl = packages[0]

        let dependents = index.dependents(of: openssl)
        #expect(dependents.map(\.name) == ["curl", "wget"])
    }

    @Test("A leaf package has no dependents")
    func leafHasNoDependents() {
        let packages = [
            pkg("openssl"),
            pkg("wget", deps: ["openssl"]),
        ]
        let index = ReverseDependencyIndex(packages: packages)
        let wget = packages[1]

        #expect(index.dependents(of: wget).isEmpty)
    }

    @Test("Lookup is scoped to manager and qualifier")
    func scopedToManagerAndQualifier() {
        let packages = [
            pkg("requests", manager: .pip, qualifier: "/venv/a", deps: []),
            pkg("urllib3", manager: .pip, qualifier: "/venv/a", deps: []),
            pkg("app-a", manager: .pip, qualifier: "/venv/a", deps: ["requests"]),
            pkg("app-b", manager: .pip, qualifier: "/venv/b", deps: ["requests"]),
        ]
        let index = ReverseDependencyIndex(packages: packages)
        let requestsA = packages[0]
        let requestsB = packages[3]

        // Only the same-qualifier app depends on /venv/a's requests.
        #expect(index.dependents(of: requestsA).map(\.name) == ["app-a"])
        // /venv/b's requests has no dependents (app-b depends on a different requests row).
        #expect(index.dependents(of: requestsB).isEmpty)
    }

    @Test("Dep names are normalized the same way as orphan analysis")
    func dependencyNamesAreNormalized() {
        let packages = [
            pkg("Requests", manager: .pip, qualifier: "/venv/a", deps: []),
            pkg("app-a", manager: .pip, qualifier: "/venv/a", deps: ["requests"]),
        ]
        let index = ReverseDependencyIndex(packages: packages)

        // PEP 503 normalization: "Requests" and "requests" collide.
        #expect(index.dependents(of: packages[0]).map(\.name) == ["app-a"])
    }

    @Test("Multi-level chains are resolved independently at each node")
    func multiLevelChains() {
        let packages = [
            pkg("a"),
            pkg("b", deps: ["a"]),
            pkg("c", deps: ["b"]),
        ]
        let index = ReverseDependencyIndex(packages: packages)

        #expect(index.dependents(of: packages[0]).map(\.name) == ["b"])
        #expect(index.dependents(of: packages[1]).map(\.name) == ["c"])
        #expect(index.dependents(of: packages[2]).isEmpty)
    }

    @Test("Unknown package id yields no dependents")
    func unknownPackageID() {
        let packages = [pkg("openssl"), pkg("wget", deps: ["openssl"])]
        let index = ReverseDependencyIndex(packages: packages)

        #expect(index.dependents(ofPackageID: "brew::missing").isEmpty)
        #expect(index.dependents(ofPackageID: "brew::openssl").map(\.name) == ["wget"])
    }

    @Test("Cycles do not affect the index (dependents are direct edges)")
    func cyclesAreHarmless() {
        let packages = [
            pkg("a", deps: ["b"]),
            pkg("b", deps: ["a"]),
        ]
        let index = ReverseDependencyIndex(packages: packages)

        #expect(index.dependents(of: packages[0]).map(\.name) == ["b"])
        #expect(index.dependents(of: packages[1]).map(\.name) == ["a"])
    }
}
