import Testing
import Foundation
@testable import InstalloryCore

@Suite("BrewScanner")
struct BrewScannerTests {

    // MARK: - Shared fixture state

    // PathDiscovery.homebrewPrefixes only probes /opt/homebrew and /usr/local.
    // Using /opt/homebrew as the fake prefix ensures checkExists hits a known candidate.
    // The scanner reads exclusively from the injected InMemoryDirectoryAccessProvider,
    // so no real filesystem access occurs even though the path looks real.
    private let fakePrefix = URL(fileURLWithPath: "/opt/homebrew")

    // MARK: - Helpers

    /// Builds an `InMemoryDirectoryAccessProvider` from the real fixture files,
    /// mapping the fixture tree under `fakePrefix` (/opt/homebrew).
    private func buildProvider() throws -> InMemoryDirectoryAccessProvider {
        try FixtureResource.provider(directory: "brew", mappedTo: fakePrefix)
    }

    private func makeScanner() throws -> BrewScanner {
        let provider = try buildProvider()
        let discovery = PathDiscovery(checkExists: { path in
            path == "/opt/homebrew"
        })
        return BrewScanner(pathDiscovery: discovery, directoryAccess: provider)
    }

    // MARK: - Availability

    @Test("isAvailable returns true when prefix exists")
    func isAvailableTrue() async throws {
        let scanner = try makeScanner()
        #expect(await scanner.isAvailable() == true)
    }

    @Test("isAvailable returns false when no prefix exists")
    func isAvailableFalse() async {
        let discovery = PathDiscovery(checkExists: { _ in false })
        let scanner = BrewScanner(
            pathDiscovery: discovery,
            directoryAccess: SystemDirectoryAccessProvider()
        )
        #expect(await scanner.isAvailable() == false)
    }

    // MARK: - Package counts and types

    @Test("scan returns packages from both Cellar and Caskroom")
    func scanReturnsBothManagers() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        let brewCount = packages.filter { $0.manager == .brew }.count
        let caskCount = packages.filter { $0.manager == .brewCask }.count
        #expect(brewCount > 0)
        #expect(caskCount > 0)
    }

    @Test("scan returns exactly 6 packages across 4 formulae and 2 casks")
    func scanTotalCount() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        #expect(packages.count == 6)
        #expect(packages.filter { $0.manager == .brew }.count == 4)
        #expect(packages.filter { $0.manager == .brewCask }.count == 2)
    }

    @Test("scan returns empty array when Cellar and Caskroom are absent")
    func scanEmptyWhenNoPrefixDirs() async throws {
        let emptyProvider = InMemoryDirectoryAccessProvider.make { _ in }
        let discovery = PathDiscovery(checkExists: { path in path == "/opt/homebrew" })
        let scanner = BrewScanner(pathDiscovery: discovery, directoryAccess: emptyProvider)
        let packages = try await scanner.scan()
        #expect(packages.isEmpty)
    }

    // MARK: - Formula correctness

    @Test("git formula has correct id, version, and install time")
    func gitFormula() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        let git = packages.first { $0.name == "git" && $0.manager == .brew }
        let g = try #require(git, "expected to find brew::git in scan results")
        #expect(g.id == "brew::git")
        #expect(g.version == "2.44.0")
        #expect(g.installedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(g.installedAtConfidence == .high)
        #expect(g.dependencies.contains("gettext"))
        #expect(g.dependencies.contains("pcre2"))
    }

    @Test("all packages have .high installedAtConfidence")
    func allPackagesHighConfidence() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        for pkg in packages {
            #expect(pkg.installedAtConfidence == .high)
        }
    }

    @Test("all packages have non-nil installPath")
    func allPackagesHaveInstallPath() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        for pkg in packages {
            #expect(pkg.installPath != nil)
        }
    }

    // MARK: - Explicit flag

    @Test("installed_on_request:true maps to isExplicit:true")
    func explicitFlagTrue() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        // wget has installed_on_request: true
        let wget = packages.first { $0.name == "wget" }
        let w = try #require(wget, "expected to find brew::wget")
        #expect(w.isExplicit == true)
    }

    @Test("installed_as_dependency:true maps to isExplicit:false")
    func explicitFlagFalse() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        // openssl@3 has installed_as_dependency: true and installed_on_request: false
        let openssl = packages.first { $0.name == "openssl@3" }
        let o = try #require(openssl, "expected to find brew::openssl@3")
        #expect(o.isExplicit == false)
    }

    // MARK: - Cask correctness

    @Test("cask ids use brewCask prefix")
    func caskIdPrefix() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        let casks = packages.filter { $0.manager == .brewCask }
        for cask in casks {
            #expect(cask.id.hasPrefix("brewCask::"))
        }
    }

    @Test("visual-studio-code cask has correct version and install time")
    func vscodeCask() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        let vscode = packages.first { $0.name == "visual-studio-code" }
        let v = try #require(vscode, "expected to find brewCask::visual-studio-code")
        #expect(v.id == "brewCask::visual-studio-code")
        // Fixture now has 1.90.2 and 1.91.0; deduplication picks 1.91.0.
        #expect(v.version == "1.91.0")
        #expect(v.installedAt == Date(timeIntervalSince1970: 1_720_000_000))
        #expect(v.isExplicit == true)
    }

    @Test("visual-studio-code cask exposes app artifact path")
    func vscodeCaskArtifactPaths() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        let vscode = packages.first { $0.name == "visual-studio-code" }
        let v = try #require(vscode, "expected to find brewCask::visual-studio-code")
        let paths = try #require(v.artifactPaths)
        #expect(paths.contains("Visual Studio Code.app"))
        #expect(paths.contains("~/Library/Application Support/Code"))
        #expect(paths.contains("~/.vscode"))
    }

    @Test("runtime dependencies strip tap-qualified prefixes")
    func tapQualifiedRuntimeDependency() async throws {
        let receipt = Data("""
            {
              "installed_as_dependency": false,
              "installed_on_request": true,
              "runtime_dependencies": [
                {"full_name": "homebrew/core/openssl@3", "version": "3.3.0"}
              ],
              "time": 1715000000
            }
            """.utf8)
        let receiptURL = fakePrefix
            .appendingPathComponent("Cellar/example/1.0.0/INSTALL_RECEIPT.json")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: receiptURL, data: receipt)
        }
        let discovery = PathDiscovery(checkExists: { path in path == "/opt/homebrew" })
        let scanner = BrewScanner(pathDiscovery: discovery, directoryAccess: provider)
        let packages = try await scanner.scan()
        let example = try #require(packages.first { $0.name == "example" })
        #expect(example.dependencies == ["openssl@3"])
    }

    @Test("python@3.12 has correct dependency list")
    func python312Dependencies() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        let python = packages.first { $0.name == "python@3.12" }
        let p = try #require(python, "expected to find brew::python@3.12")
        #expect(p.dependencies.contains("openssl@3"))
        #expect(p.dependencies.contains("sqlite"))
        #expect(p.dependencies.count == 4)
    }

    // MARK: - Package properties

    @Test("brew packages have nil qualifier")
    func noQualifier() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        for pkg in packages {
            #expect(pkg.qualifier == nil)
        }
    }

    @Test("brew packages are not read-only")
    func notReadOnly() async throws {
        let scanner = try makeScanner()
        let packages = try await scanner.scan()
        for pkg in packages {
            #expect(pkg.isReadOnly == false)
        }
    }

    // MARK: - Version deduplication

    private func minimalReceiptData() -> Data {
        Data(#"{"installed_on_request":true,"time":1700000000}"#.utf8)
    }

    @Test("two versions of a formula emit one Package with the higher version")
    func twoVersionsFormulaPicksLatest() async throws {
        let receipt = minimalReceiptData()
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: fakePrefix.appendingPathComponent("Cellar/test-formula/1.0.0/INSTALL_RECEIPT.json"), data: receipt)
            builder.addFile(at: fakePrefix.appendingPathComponent("Cellar/test-formula/1.0.1/INSTALL_RECEIPT.json"), data: receipt)
        }
        let discovery = PathDiscovery(checkExists: { $0 == "/opt/homebrew" })
        let scanner = BrewScanner(pathDiscovery: discovery, directoryAccess: provider)
        let packages = try await scanner.scan()
        #expect(packages.count == 1)
        let pkg = try #require(packages.first)
        #expect(pkg.version == "1.0.1")
    }

    @Test("three versions of a formula emit one Package with the highest version")
    func threeVersionsFormulaPicksHighest() async throws {
        let receipt = minimalReceiptData()
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: fakePrefix.appendingPathComponent("Cellar/test-formula/2.0.0/INSTALL_RECEIPT.json"), data: receipt)
            builder.addFile(at: fakePrefix.appendingPathComponent("Cellar/test-formula/2.1.0/INSTALL_RECEIPT.json"), data: receipt)
            builder.addFile(at: fakePrefix.appendingPathComponent("Cellar/test-formula/2.0.9/INSTALL_RECEIPT.json"), data: receipt)
        }
        let discovery = PathDiscovery(checkExists: { $0 == "/opt/homebrew" })
        let scanner = BrewScanner(pathDiscovery: discovery, directoryAccess: provider)
        let packages = try await scanner.scan()
        #expect(packages.count == 1)
        let pkg = try #require(packages.first)
        #expect(pkg.version == "2.1.0")
    }

    @Test("ambiguous version comparison falls back to newer INSTALL_RECEIPT.json mtime")
    func ambiguousVersionFallsBackToMtime() async throws {
        let receipt = minimalReceiptData()
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_720_000_000)
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: fakePrefix.appendingPathComponent("Cellar/test-formula/1.0.0-alpha/INSTALL_RECEIPT.json"),
                data: receipt,
                modificationDate: olderDate
            )
            builder.addFile(
                at: fakePrefix.appendingPathComponent("Cellar/test-formula/1.0.0-beta/INSTALL_RECEIPT.json"),
                data: receipt,
                modificationDate: newerDate
            )
        }
        let discovery = PathDiscovery(checkExists: { $0 == "/opt/homebrew" })
        let scanner = BrewScanner(pathDiscovery: discovery, directoryAccess: provider)
        let packages = try await scanner.scan()
        #expect(packages.count == 1)
        let pkg = try #require(packages.first)
        #expect(pkg.version == "1.0.0-beta")
    }

    @Test("cask with two versions emits one Package with the higher version")
    func caskTwoVersionsPicksLatest() async throws {
        let receipt = minimalReceiptData()
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: fakePrefix.appendingPathComponent("Caskroom/my-cask/1.0.0/INSTALL_RECEIPT.json"), data: receipt)
            builder.addFile(at: fakePrefix.appendingPathComponent("Caskroom/my-cask/1.1.0/INSTALL_RECEIPT.json"), data: receipt)
        }
        let discovery = PathDiscovery(checkExists: { $0 == "/opt/homebrew" })
        let scanner = BrewScanner(pathDiscovery: discovery, directoryAccess: provider)
        let packages = try await scanner.scan()
        #expect(packages.count == 1)
        let pkg = try #require(packages.first)
        #expect(pkg.version == "1.1.0")
        #expect(pkg.manager == .brewCask)
    }

    // MARK: - CORE-01: dual-prefix deduplication

    private let intelPrefix = URL(fileURLWithPath: "/usr/local")

    /// Both Homebrew prefixes present, as on an Apple Silicon Mac that also runs
    /// Rosetta workloads. `PathDiscovery` reports them Apple Silicon first.
    private func dualPrefixDiscovery() -> PathDiscovery {
        PathDiscovery(checkExists: { $0 == "/opt/homebrew" || $0 == "/usr/local" })
    }

    @Test("CORE-01: a formula under both prefixes emits one Package, not a duplicate id")
    func dualPrefixFormulaDeduplicates() async throws {
        let receipt = minimalReceiptData()
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: fakePrefix.appendingPathComponent("Cellar/openssl@3/3.3.0/INSTALL_RECEIPT.json"), data: receipt)
            builder.addFile(at: intelPrefix.appendingPathComponent("Cellar/openssl@3/3.1.0/INSTALL_RECEIPT.json"), data: receipt)
        }
        let scanner = BrewScanner(pathDiscovery: dualPrefixDiscovery(), directoryAccess: provider)
        let packages = try await scanner.scan()

        #expect(packages.count == 1)
        #expect(Set(packages.map(\.id)).count == packages.count)
    }

    @Test("CORE-01: dual-prefix dedup keeps the Apple Silicon (/opt/homebrew) copy")
    func dualPrefixPrefersAppleSiliconPrefix() async throws {
        let receipt = minimalReceiptData()
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: fakePrefix.appendingPathComponent("Cellar/openssl@3/3.3.0/INSTALL_RECEIPT.json"), data: receipt)
            builder.addFile(at: intelPrefix.appendingPathComponent("Cellar/openssl@3/3.1.0/INSTALL_RECEIPT.json"), data: receipt)
        }
        let scanner = BrewScanner(pathDiscovery: dualPrefixDiscovery(), directoryAccess: provider)
        let pkg = try #require(try await scanner.scan().first)

        #expect(pkg.version == "3.3.0")
        #expect(pkg.installPath?.path.hasPrefix("/opt/homebrew") == true)
    }

    @Test("CORE-01: a cask under both prefixes emits one Package")
    func dualPrefixCaskDeduplicates() async throws {
        let receipt = minimalReceiptData()
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: fakePrefix.appendingPathComponent("Caskroom/my-cask/1.0.0/INSTALL_RECEIPT.json"), data: receipt)
            builder.addFile(at: intelPrefix.appendingPathComponent("Caskroom/my-cask/1.0.0/INSTALL_RECEIPT.json"), data: receipt)
        }
        let scanner = BrewScanner(pathDiscovery: dualPrefixDiscovery(), directoryAccess: provider)
        let packages = try await scanner.scan()

        #expect(packages.count == 1)
        #expect(packages.first?.manager == .brewCask)
    }

    @Test("CORE-01: prefix-only packages from both prefixes are all retained")
    func dualPrefixDisjointPackagesAllSurvive() async throws {
        let receipt = minimalReceiptData()
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: fakePrefix.appendingPathComponent("Cellar/arm-only/1.0.0/INSTALL_RECEIPT.json"), data: receipt)
            builder.addFile(at: intelPrefix.appendingPathComponent("Cellar/intel-only/1.0.0/INSTALL_RECEIPT.json"), data: receipt)
        }
        let scanner = BrewScanner(pathDiscovery: dualPrefixDiscovery(), directoryAccess: provider)
        let packages = try await scanner.scan()

        #expect(Set(packages.map(\.name)) == ["arm-only", "intel-only"])
    }

    // MARK: - CORE-05: bounded package sizes

    @Test("CORE-05: formula size is the exact logical size of its selected keg")
    func formulaSizeUsesSelectedKegTree() async throws {
        let versionDir = fakePrefix.appendingPathComponent("Cellar/sized-formula/1.0.0")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: versionDir.appendingPathComponent("INSTALL_RECEIPT.json"),
                data: minimalReceiptData(),
                logicalSizeBytes: 10
            )
            builder.addFile(
                at: versionDir.appendingPathComponent("bin/sized-formula"),
                data: Data(),
                logicalSizeBytes: 90
            )
            builder.addFile(
                at: versionDir.appendingPathComponent("share/man/man1/sized-formula.1"),
                data: Data(),
                logicalSizeBytes: 25
            )
        }
        let discovery = PathDiscovery(checkExists: { $0 == self.fakePrefix.path })

        let package = try #require(try await BrewScanner(
            pathDiscovery: discovery,
            directoryAccess: provider
        ).scan().first)

        #expect(package.sizeBytes == 125)
    }

    @Test("CORE-05: cask size counts app bundles but never receipt or zap paths")
    func caskSizeCountsOnlyInstalledAppBundle() async throws {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let versionDir = fakePrefix.appendingPathComponent("Caskroom/sized-cask/1.0.0")
        let receipt = Data("""
            {
              "installed_on_request": true,
              "artifacts": [
                {"app": ["Sized App.app"]},
                {"zap": [{"trash": ["~/Library/Application Support/Sized App"]}]}
              ]
            }
            """.utf8)
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: versionDir.appendingPathComponent("INSTALL_RECEIPT.json"),
                data: receipt,
                logicalSizeBytes: 1_000
            )
            builder.addFile(
                at: applications.appendingPathComponent("Sized App.app/Contents/MacOS/Sized App"),
                data: Data(),
                logicalSizeBytes: 120
            )
            builder.addFile(
                at: applications.appendingPathComponent("Sized App.app/Contents/Resources/icon.icns"),
                data: Data(),
                logicalSizeBytes: 30
            )
            builder.addFile(
                at: URL(fileURLWithPath: "/Users/tester/Library/Application Support/Sized App/cache"),
                data: Data(),
                logicalSizeBytes: 50_000
            )
        }
        let discovery = PathDiscovery(checkExists: { $0 == self.fakePrefix.path })

        let package = try #require(try await BrewScanner(
            pathDiscovery: discovery,
            directoryAccess: provider,
            applicationDirectories: [applications]
        ).scan().first)

        #expect(package.manager == .brewCask)
        #expect(package.sizeBytes == 150)
    }

    @Test("CORE-05: cask app artifacts with path components are rejected")
    func unsafeCaskAppArtifactHasUnknownSize() async throws {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let versionDir = fakePrefix.appendingPathComponent("Caskroom/unsafe-cask/1.0.0")
        let receipt = Data("""
            {
              "installed_on_request": true,
              "artifacts": [{"app": ["Nested/Evil.app"]}]
            }
            """.utf8)
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: versionDir.appendingPathComponent("INSTALL_RECEIPT.json"),
                data: receipt
            )
            builder.addFile(
                at: applications.appendingPathComponent("Nested/Evil.app/Contents/MacOS/Evil"),
                data: Data(),
                logicalSizeBytes: 777
            )
        }
        let discovery = PathDiscovery(checkExists: { $0 == self.fakePrefix.path })

        let package = try #require(try await BrewScanner(
            pathDiscovery: discovery,
            directoryAccess: provider,
            applicationDirectories: [applications]
        ).scan().first)

        #expect(package.sizeBytes == nil)
    }

    @Test("CORE-05: Brew scanning propagates task cancellation")
    func brewScanningPropagatesCancellation() async {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: fakePrefix.appendingPathComponent("Cellar/tool/1.0.0/INSTALL_RECEIPT.json"),
                data: minimalReceiptData()
            )
        }
        let discovery = PathDiscovery(checkExists: { $0 == self.fakePrefix.path })
        let scanner = BrewScanner(pathDiscovery: discovery, directoryAccess: provider)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
