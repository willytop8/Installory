import InstalloryCore
import Foundation
import Testing

@Suite("Package filtering")
struct PackageFilterTests {
    // MARK: - Fixtures

    private static let ref = Date(timeIntervalSince1970: 1_710_000_000)

    private func pkg(
        _ name: String,
        manager: PackageManager,
        qualifier: String? = nil,
        installPath: URL? = nil,
        isReadOnly: Bool = false
    ) -> Package {
        Package(
            id: "\(manager.rawValue)::\(name)",
            manager: manager,
            qualifier: qualifier,
            name: name,
            version: "1.0.0",
            installPath: installPath,
            installedAt: Self.ref,
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: isReadOnly,
            dependencies: [],
            lastSeen: Self.ref
        )
    }

    private var packages: [Package] {
        [
            pkg("ffmpeg", manager: .brew),
            pkg("openssl", manager: .brew),
            pkg("requests", manager: .pip),
            pkg("black", manager: .pip),
            pkg("typescript", manager: .npm),
            pkg("python3", manager: .brew, isReadOnly: true),
        ]
    }

    // MARK: - Tests

    @Test(".all returns every package unfiltered")
    func filterAll() {
        let result = packages.filtered(by: .all, query: "")
        #expect(result.count == packages.count)
    }

    @Test(".manager(.brew) returns only Homebrew packages")
    func filterBrew() {
        let result = packages.filtered(by: .manager(.brew), query: "")
        let allBrew = result.allSatisfy { $0.manager == .brew }
        #expect(allBrew)
        #expect(result.count == 3)
    }

    @Test(".manager(.pip) returns only pip packages")
    func filterPip() {
        let result = packages.filtered(by: .manager(.pip), query: "")
        let allPip = result.allSatisfy { $0.manager == .pip }
        #expect(allPip)
        #expect(result.count == 2)
    }

    @Test(".readOnly returns only read-only packages")
    func filterReadOnly() {
        let result = packages.filtered(by: .readOnly, query: "")
        let allReadOnly = result.allSatisfy { $0.isReadOnly }
        #expect(allReadOnly)
        #expect(result.count == 1)
        #expect(result.first?.name == "python3")
    }

    @Test("nil selection behaves like .all")
    func filterNil() {
        let result = packages.filtered(by: nil, query: "")
        #expect(result.count == packages.count)
    }

    @Test("query narrows results within a manager filter")
    func filterBrewWithQuery() {
        let result = packages.filtered(by: .manager(.brew), query: "ff")
        #expect(result.count == 1)
        #expect(result.first?.name == "ffmpeg")
    }

    @Test("query is case-insensitive")
    func queryIsCaseInsensitive() {
        let result = packages.filtered(by: .all, query: "REQUESTS")
        #expect(result.count == 1)
        #expect(result.first?.name == "requests")
    }

    @Test("empty query with .all returns all packages")
    func emptyQueryAll() {
        let result = packages.filtered(by: .all, query: "")
        #expect(result.count == packages.count)
    }

    @Test("APP-F1: search matches a manager qualifier")
    func queryMatchesQualifier() {
        let scoped = pkg(
            "ruff",
            manager: .pip,
            qualifier: "/Users/test/.pyenv/versions/3.12/bin/python"
        )

        #expect([scoped].matching(query: "PYENV").map(\.id) == [scoped.id])
    }

    @Test("APP-F1: search matches an install path case-insensitively")
    func queryMatchesInstallPath() {
        let scoped = pkg(
            "typescript",
            manager: .npm,
            installPath: URL(fileURLWithPath: "/Users/Test/.nvm/versions/node/v22/lib/node_modules/typescript")
        )

        #expect([scoped].matching(query: ".NVM/VERSIONS").map(\.id) == [scoped.id])
    }

    @Test("APP-F1: whitespace-only search preserves every package in input order")
    func whitespaceQueryPreservesInput() {
        #expect(packages.matching(query: "  \n\t ").map(\.id) == packages.map(\.id))
    }

    @Test("APP-F1: unrelated search matches no package fields")
    func unrelatedQueryMatchesNothing() {
        let scoped = pkg(
            "ruff",
            manager: .pip,
            qualifier: "/Users/test/.pyenv/versions/3.12/bin/python",
            installPath: URL(fileURLWithPath: "/Users/test/.pyenv/versions/3.12/lib/python/site-packages/ruff")
        )

        #expect([scoped].matching(query: "definitely-not-present").isEmpty)
    }
}
