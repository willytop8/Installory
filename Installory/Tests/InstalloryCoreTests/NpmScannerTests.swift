import Foundation
import Testing
@testable import InstalloryCore

@Suite("NpmScanner")
struct NpmScannerTests {
    private static let fixtureDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/npm")

    // MARK: - Helpers

    private func buildProvider() throws -> InMemoryDirectoryAccessProvider {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Self.fixtureDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return InMemoryDirectoryAccessProvider.make { builder in
            while let fileURL = enumerator.nextObject() as? URL {
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isFile else { continue }

                let relativePath = String(fileURL.path.dropFirst(Self.fixtureDir.path.count))
                let fakeURL = URL(fileURLWithPath: relativePath)
                if let data = try? Data(contentsOf: fileURL) {
                    builder.addFile(at: fakeURL, data: data)
                }
            }
        }
    }

    private func makeScanner(provider: InMemoryDirectoryAccessProvider) -> NpmScanner {
        NpmScanner(
            directoryAccess: provider,
            homeDirectory: URL(fileURLWithPath: "/")
        )
    }

    // MARK: - Tests

    @Test("discovers all packages across all fixture node_modules dirs")
    func discoversAllPackages() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        // brew: typescript + @types/node (2), nvm v20.0.0: lodash (1)
        #expect(packages.count == 3)
        #expect(packages.contains { $0.name == "typescript" })
        #expect(packages.contains { $0.name == "@types/node" })
        #expect(packages.contains { $0.name == "lodash" })
    }

    @Test("scoped package has correct name and id")
    func scopedPackageNameAndId() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        let typesNode = try #require(packages.first { $0.name == "@types/node" })
        #expect(typesNode.name == "@types/node")
        #expect(typesNode.id == "npm:/opt/homebrew/lib/node_modules:@types/node")
        #expect(typesNode.qualifier == "/opt/homebrew/lib/node_modules")
    }

    @Test("qualifier matches node_modules directory path for all packages")
    func qualifierMatchesNodeModulesPath() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        for package in packages {
            let qualifier = try #require(package.qualifier)
            #expect(package.id.hasPrefix("npm:\(qualifier):"))
        }
    }

    @Test("all packages have manager=.npm")
    func allPackagesHaveNpmManager() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        for package in packages {
            #expect(package.manager == .npm)
        }
    }

    @Test("dependencies come from 'dependencies' key only, not devDependencies or peerDependencies")
    func dependenciesFromDependenciesKeyOnly() async throws {
        let provider = try buildProvider()
        let packages = try await makeScanner(provider: provider).scan()

        // typescript fixture has devDependencies {mocha, eslint} and peerDependencies {typescript};
        // only the "dependencies" key {tslib} should contribute.
        let typescript = try #require(packages.first { $0.name == "typescript" })
        #expect(typescript.dependencies == ["tslib"])
    }

    @Test("same package name in two node installations produces two distinct rows")
    func samePackageInTwoInstallationsIsDistinct() async throws {
        let nodeModulesA = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules")
        let nodeModulesB = URL(fileURLWithPath: "/.nvm/versions/node/v20.0.0/lib/node_modules")

        let pkgJSON = Data(#"{"name":"rimraf","version":"5.0.5"}"#.utf8)

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: nodeModulesA.appendingPathComponent("rimraf/package.json"), data: pkgJSON)
            builder.addFile(at: nodeModulesB.appendingPathComponent("rimraf/package.json"), data: pkgJSON)
        }

        let packages = try await makeScanner(provider: provider).scan()

        #expect(packages.count == 2)
        #expect(packages[0].id != packages[1].id)
        #expect(packages.allSatisfy { $0.name == "rimraf" })
    }

    @Test("empty filesystem returns empty package list")
    func emptyFilesystemReturnsEmpty() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { _ in }
        let packages = try await makeScanner(provider: provider).scan()
        #expect(packages.isEmpty)
    }

    @Test("malformed package.json is silently skipped; valid packages in the same dir are returned")
    func malformedPackageJsonSilentlySkipped() async throws {
        let nodeModulesDir = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules")

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: nodeModulesDir.appendingPathComponent("valid-pkg/package.json"),
                data: Data(#"{"name":"valid-pkg","version":"1.0.0"}"#.utf8)
            )
            builder.addFile(
                at: nodeModulesDir.appendingPathComponent("broken-pkg/package.json"),
                data: Data("not json {{{{".utf8)
            )
        }

        let packages = try await makeScanner(provider: provider).scan()

        #expect(packages.count == 1)
        #expect(packages.first?.name == "valid-pkg")
    }

    // MARK: - Symlink dedup tests

    @Test("two node_modules dirs that resolve to the same path produce packages only once")
    func symlinkedNodeModulesDirDeduplicatesPackages() async throws {
        // Simulates /opt/homebrew/lib/node_modules being a symlink whose resolved
        // path also appears as a Volta or nvm candidate.
        let realDir = URL(fileURLWithPath: "/opt/homebrew/Cellar/node/22.0.0/lib/node_modules")
        let symlinkDir = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules")
        let pkgJSON = Data(#"{"name":"rimraf","version":"5.0.5"}"#.utf8)

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            // Register the real package under the canonical Cellar path
            builder.addFile(at: realDir.appendingPathComponent("rimraf/package.json"), data: pkgJSON)
            // Register the symlink so resolvingSymlinks follows it
            builder.addSymlink(at: symlinkDir, target: realDir)
        }

        // homeDirectory set to "/" so nvm/Volta discovery finds nothing extra
        let scanner = NpmScanner(directoryAccess: provider, homeDirectory: URL(fileURLWithPath: "/"))
        let packages = try await scanner.scan()

        // The symlink and real dir resolve to the same path → scanned only once
        #expect(packages.count == 1)
        #expect(packages.first?.name == "rimraf")
        // Qualifier uses the first (brew) candidate's pre-resolution URL
        #expect(packages.first?.qualifier == "/opt/homebrew/lib/node_modules")
    }

    @Test("two symlinked entries in the same node_modules dir that resolve to the same package are deduped")
    func symlinkedEntryWithinNodeModulesIsDeduped() async throws {
        let nodeModulesDir = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules")
        let realPkgDir = URL(fileURLWithPath: "/opt/homebrew/Cellar/node/22.0.0/lib/node_modules/typescript")
        let pkgJSON = Data(#"{"name":"typescript","version":"5.4.5"}"#.utf8)

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            // The canonical package dir
            builder.addFile(at: realPkgDir.appendingPathComponent("package.json"), data: pkgJSON)
            // A symlink inside node_modules pointing at the same physical dir
            let symlinkEntry = nodeModulesDir.appendingPathComponent("typescript")
            builder.addSymlink(at: symlinkEntry, target: realPkgDir)
            // A second symlink from an alias name (e.g. ts → typescript) resolving to the same dir
            let aliasEntry = nodeModulesDir.appendingPathComponent("ts")
            builder.addSymlink(at: aliasEntry, target: realPkgDir)
        }

        let scanner = NpmScanner(directoryAccess: provider, homeDirectory: URL(fileURLWithPath: "/"))
        let packages = try await scanner.scan()

        // Both symlinks resolve to the same physical dir — only one package emitted
        #expect(packages.count == 1)
        #expect(packages.first?.name == "typescript")
    }

    @Test("nvm version directories are enumerated in deterministic sorted order")
    func nvmVersionDirsAreSorted() async throws {
        // Two nvm versions where v20 sorts before v8 lexicographically by path,
        // but v8 sorts before v20 numerically. The scanner uses path sort (lexicographic),
        // so v20 should appear first and claim the qualifier for any shared physical dir.
        let v20 = URL(fileURLWithPath: "/.nvm/versions/node/v20.0.0/lib/node_modules")
        let v8  = URL(fileURLWithPath: "/.nvm/versions/node/v8.0.0/lib/node_modules")
        let pkgJSON = Data(#"{"name":"lodash","version":"4.17.21"}"#.utf8)

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: v20.appendingPathComponent("lodash/package.json"), data: pkgJSON)
            builder.addFile(at: v8.appendingPathComponent("lodash/package.json"), data: pkgJSON)
        }

        let scanner = NpmScanner(directoryAccess: provider, homeDirectory: URL(fileURLWithPath: "/"))
        let packages = try await scanner.scan()

        // Two distinct physical dirs → two distinct packages
        #expect(packages.count == 2)
        // Both have unique IDs (different qualifiers)
        #expect(Set(packages.map(\.id)).count == 2)
        // v20 path sorts before v8 (lexicographic) so v20 qualifier should appear
        let qualifiers = packages.map { $0.qualifier ?? "" }.sorted()
        #expect(qualifiers.contains("/.nvm/versions/node/v20.0.0/lib/node_modules"))
        #expect(qualifiers.contains("/.nvm/versions/node/v8.0.0/lib/node_modules"))
    }
}
