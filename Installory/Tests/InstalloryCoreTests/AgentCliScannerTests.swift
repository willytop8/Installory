import Foundation
import Testing
@testable import InstalloryCore

@Suite("AgentCliScanner")
struct AgentCliScannerTests {
    private let claudeRoot = URL(fileURLWithPath: "/Users/tester/.claude")
    private let codexRoot = URL(fileURLWithPath: "/Users/tester/.codex")
    private let opencodeRoot = URL(fileURLWithPath: "/Users/tester/.config/opencode")
    private let cursorRoot = URL(fileURLWithPath: "/Users/tester/.cursor")

    private func makeScanner(
        roots: [URL],
        provider: InMemoryDirectoryAccessProvider
    ) -> AgentCliScanner {
        AgentCliScanner(
            cliRoots: roots,
            directoryAccess: provider,
            limits: .default,
            now: { Date(timeIntervalSince1970: 1_717_000_000) }
        )
    }

    @Test("reads an agent CLI config root")
    func readsClaudeRoot() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: claudeRoot.appendingPathComponent("settings.json"),
                data: Data("{}".utf8),
                logicalSizeBytes: 2
            )
        }

        let packages = try await makeScanner(roots: [claudeRoot], provider: provider).scan()

        #expect(packages.count == 1)
        let package = try #require(packages.first)
        #expect(package.manager == .agentCli)
        #expect(package.id == "agentCli:\(claudeRoot.path):claude")
        #expect(package.qualifier == claudeRoot.path)
        #expect(package.name == "claude")
        #expect(package.installPath == claudeRoot)
        #expect(package.isExplicit)
        #expect(!package.isReadOnly)
        #expect((package.sizeBytes ?? 0) > 0)
    }

    @Test("reads version from package.json inside the config root")
    func versionFromPackageJSON() async throws {
        let manifest = #"{"name":"opencode","version":"0.1.2"}"#
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: opencodeRoot.appendingPathComponent("package.json"),
                data: Data(manifest.utf8)
            )
        }

        let packages = try await makeScanner(roots: [opencodeRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.name == "opencode")
        #expect(package.version == "0.1.2")
    }

    @Test("reads version from a plain version file")
    func versionFromVersionFile() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: codexRoot.appendingPathComponent("version"),
                data: Data("1.2.3".utf8)
            )
        }

        let packages = try await makeScanner(roots: [codexRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.name == "codex")
        #expect(package.version == "1.2.3")
    }

    @Test("version is empty when no version marker is present")
    func unversionedRoot() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: cursorRoot)
        }

        let packages = try await makeScanner(roots: [cursorRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.name == "cursor")
        #expect(package.version == "")
    }

    @Test("scans multiple roots and tags each CLI with its own config root")
    func scansMultipleRoots() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: claudeRoot)
            builder.addDirectory(at: codexRoot)
        }

        let packages = try await makeScanner(
            roots: [claudeRoot, codexRoot],
            provider: provider
        ).scan()

        #expect(packages.count == 2)
        #expect(packages.map(\.name).sorted() == ["claude", "codex"])
        let claude = try #require(packages.first { $0.name == "claude" })
        #expect(claude.qualifier == claudeRoot.path)
        let codex = try #require(packages.first { $0.name == "codex" })
        #expect(codex.qualifier == codexRoot.path)
    }

    @Test("isAvailable is false when no root exists")
    func availabilityRequiresExistingRoot() async throws {
        let empty = InMemoryDirectoryAccessProvider.make { _ in }
        let scanner = makeScanner(roots: [claudeRoot], provider: empty)
        #expect(await scanner.isAvailable() == false)

        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: claudeRoot)
        }
        #expect(await makeScanner(roots: [claudeRoot], provider: present).isAvailable() == true)
    }

    @Test("discovery finds only the agent CLI config roots that exist")
    func discoveryFindsExistingRoots() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: home.appendingPathComponent(".claude"))
            builder.addDirectory(at: home.appendingPathComponent(".codex"))
            // .config/opencode and .cursor are intentionally absent.
        }

        let roots = AgentCliDiscovery.cliRoots(homeDirectory: home, directoryAccess: provider)

        #expect(roots.map(\.path) == [
            home.appendingPathComponent(".claude").path,
            home.appendingPathComponent(".codex").path,
        ])
    }
}
