import InstalloryCore
import Foundation
import Testing

@Suite("Orphaned-package dependency analysis")
struct DependencyAnalysisTests {

    // Fixed reference timestamp so tests are deterministic.
    private static let ref = Date(timeIntervalSince1970: 1_710_000_000)

    /// Minimal package factory. All fields not relevant to orphan logic default
    /// to safe, neutral values.
    private func pkg(
        _ name: String,
        manager: PackageManager = .brew,
        qualifier: String? = nil,
        explicit: Bool = true,
        readOnly: Bool = false,
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
            isExplicit: explicit,
            isReadOnly: readOnly,
            dependencies: deps,
            lastSeen: Self.ref
        )
    }

    // MARK: - Basic orphan detection

    @Test("Explicit leaf with no dependents is an orphan")
    func explicitLeafIsOrphan() {
        let packages = [pkg("ripgrep")]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        #expect(orphans.count == 1)
        #expect(orphans[0].name == "ripgrep")
    }

    @Test("Explicit package depended on by another explicit package is NOT an orphan")
    func dependedUponPackageIsNotOrphan() {
        let packages = [
            pkg("openssl", explicit: true, deps: []),
            pkg("wget", explicit: true, deps: ["openssl"]),
        ]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        // wget has no dependents → orphan; openssl is needed by wget → not orphan
        #expect(orphans.map(\.name) == ["wget"])
    }

    @Test("Non-explicit (dependency-only) package is NOT listed even if it is a leaf")
    func nonExplicitIsNeverAnOrphan() {
        let packages = [pkg("dep-lib", explicit: false, deps: [])]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        #expect(orphans.isEmpty)
    }

    @Test("Non-explicit dependency that others depend on is also not listed")
    func nonExplicitWithDependentsIsNeverAnOrphan() {
        let packages = [
            pkg("libssl", explicit: false, deps: []),
            pkg("curl", explicit: true, deps: ["libssl"]),
        ]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        // libssl is non-explicit → excluded; curl has no dependents → orphan
        let names = orphans.map(\.name)
        #expect(!names.contains("libssl"))
        #expect(names.contains("curl"))
    }

    // MARK: - Denylist exclusion

    @Test("Denylisted essential (git) is excluded even when it has no dependents")
    func denylistedEssentialExcluded() {
        // Use the real default denylist — git is denylisted for brew.
        let packages = [pkg("git", manager: .brew)]
        let orphans = packages.orphanedPackages()
        #expect(orphans.isEmpty)
    }

    @Test("Custom empty denylist allows a normally-denylisted name through")
    func emptyDenylistAllowsEverything() {
        let packages = [pkg("git", manager: .brew)]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        #expect(orphans.count == 1)
    }

    // MARK: - Read-only exclusion

    @Test("Read-only package is never an orphan candidate")
    func readOnlyPackageExcluded() {
        // pip setuptools is commonly read-only; use a neutral name to avoid
        // hitting the default denylist.
        let packages = [pkg("mylib", manager: .cargo, readOnly: true)]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        #expect(orphans.isEmpty)
    }

    // MARK: - Case-insensitive matching

    @Test("Dependent matching is case-insensitive (mixed-case package name)")
    func caseInsensitiveMatching() {
        // "OpenSSL" is the package name; "wget" refers to it as "openssl" (lowercase).
        let packages = [
            pkg("OpenSSL", manager: .brew, explicit: true, deps: []),
            pkg("wget", manager: .brew, explicit: true, deps: ["openssl"]),
        ]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        let names = orphans.map(\.name)
        // OpenSSL is depended on → not an orphan
        #expect(!names.contains("OpenSSL"))
        // wget has no dependents → orphan
        #expect(names.contains("wget"))
    }

    // MARK: - Determinism and immutability

    @Test("Result is sorted by manager raw value then name — deterministic order")
    func deterministicOrder() {
        // brew < cargo < npm alphabetically; alpha < zebra within brew
        let packages = [
            pkg("zebra", manager: .brew),
            pkg("alpha", manager: .brew),
            pkg("tool", manager: .npm),
            pkg("util", manager: .cargo),
        ]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        #expect(orphans.map(\.name) == ["alpha", "zebra", "util", "tool"])
    }

    @Test("APP25-022: case-insensitive orphan sort ties break by stable package ID")
    func deterministicOrderForEqualFoldedNames() {
        let packages = [
            pkg("alpha", manager: .brew),
            pkg("Alpha", manager: .brew),
        ]

        let ids = Array(packages.reversed())
            .orphanedPackages(denylist: Denylist(entries: []))
            .map(\.id)

        #expect(ids == ids.sorted())
    }

    @Test("Input array is not mutated — calling twice returns identical results")
    func inputImmutable() {
        let packages = [
            pkg("a", manager: .pipx),
            pkg("b", manager: .pipx),
            pkg("c", manager: .pipx),
        ]
        let first  = packages.orphanedPackages(denylist: Denylist(entries: []))
        let second = packages.orphanedPackages(denylist: Denylist(entries: []))
        #expect(first.map(\.name) == second.map(\.name))
    }

    // MARK: - Cross-manager isolation

    @Test("Cross-manager dependencies are ignored — each manager's graph is independent")
    func crossManagerIndependence() {
        // brew "ffmpeg" depends on "aom" (brew); npm "aom" is a separate package.
        // npm aom should have no npm dependents → is an orphan.
        // brew ffmpeg should have no brew dependents → is also an orphan.
        let packages = [
            pkg("ffmpeg", manager: .brew, explicit: true, deps: ["aom"]),
            pkg("aom",    manager: .npm,  explicit: true, deps: []),
        ]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        let names = Set(orphans.map(\.name))
        #expect(names == ["ffmpeg", "aom"])
    }

    @Test("brew package depended on within brew is not an orphan even if npm has same name")
    func crossManagerDoesNotSuppressBrewOrphan() {
        // brew curl depends on brew openssl.
        // npm has its own "openssl" — it should not count as a dependent of brew openssl.
        let packages = [
            pkg("openssl", manager: .brew, explicit: true, deps: []),
            pkg("curl",    manager: .brew, explicit: true, deps: ["openssl"]),
            pkg("openssl", manager: .npm,  explicit: true, deps: []),
        ]
        let orphans = packages.orphanedPackages(denylist: Denylist(entries: []))
        let names = orphans.map(\.name)
        // brew openssl has a brew dependent (curl) → not an orphan
        let brewOrphans = orphans.filter { $0.manager == .brew }.map(\.name)
        #expect(!brewOrphans.contains("openssl"))
        // npm openssl has no npm dependents → orphan
        let npmOrphans = orphans.filter { $0.manager == .npm }.map(\.name)
        #expect(npmOrphans.contains("openssl"))
        // brew curl has no brew dependents → orphan
        #expect(names.contains("curl"))
    }

    // MARK: - Qualifier and package-name identity

    @Test("CORE25-008: a dependency protects only the matching manager qualifier")
    func dependencyIsIsolatedByQualifier() {
        let python311 = "/opt/homebrew/bin/python3.11"
        let python312 = "/opt/homebrew/bin/python3.12"
        let packages = [
            pkg("requests", manager: .pip, qualifier: python311),
            pkg("requests", manager: .pip, qualifier: python312),
            pkg("api-client", manager: .pip, qualifier: python311, deps: ["requests"]),
        ]

        let orphanIds = Set(
            packages
                .orphanedPackages(denylist: Denylist(entries: []))
                .map(\.id)
        )

        #expect(!orphanIds.contains("pip:\(python311):requests"))
        #expect(orphanIds.contains("pip:\(python312):requests"))
        #expect(orphanIds.contains("pip:\(python311):api-client"))
    }

    @Test("CORE25-008: pip dependency matching applies PEP 503 normalization")
    func pipDependencyUsesPEP503Normalization() {
        let interpreter = "/usr/bin/python3"
        let packages = [
            pkg("Requests_OAuthLib", manager: .pip, qualifier: interpreter),
            pkg(
                "auth-client",
                manager: .pip,
                qualifier: interpreter,
                deps: ["requests...oauthlib"]
            ),
        ]

        let orphanNames = packages
            .orphanedPackages(denylist: Denylist(entries: []))
            .map(\.name)

        #expect(orphanNames == ["auth-client"])
    }

    @Test("CORE25-008: PEP 503 separator folding is not applied to other managers")
    func nonPythonManagersPreservePackageSeparators() {
        let packages = [
            pkg("my_gem", manager: .gem),
            pkg("consumer", manager: .gem, deps: ["my-gem"]),
        ]

        let orphanNames = Set(
            packages
                .orphanedPackages(denylist: Denylist(entries: []))
                .map(\.name)
        )

        #expect(orphanNames == ["my_gem", "consumer"])
    }
}
