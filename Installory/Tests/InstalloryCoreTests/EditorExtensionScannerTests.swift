import Foundation
import Testing
@testable import InstalloryCore

@Suite("EditorExtensionScanner")
struct EditorExtensionScannerTests {
    private let vscodeRoot = URL(fileURLWithPath: "/Users/tester/.vscode/extensions")
    private let cursorRoot = URL(fileURLWithPath: "/Users/tester/.cursor/extensions")

    private func makeScanner(
        roots: [URL],
        provider: InMemoryDirectoryAccessProvider
    ) -> EditorExtensionScanner {
        EditorExtensionScanner(
            extensionRoots: roots,
            directoryAccess: provider,
            limits: .default,
            now: { Date(timeIntervalSince1970: 1_717_000_000) }
        )
    }

    private func packageJSON(name: String, version: String) -> String {
        #"{"name":"\#(name)","version":"\#(version)","publisher":"esbenp"}"#
    }

    @Test("reads a VS Code extension with package.json metadata")
    func readsVSCODExtension() async throws {
        let dir = vscodeRoot.appendingPathComponent("esbenp.prettier-vscode-10.1.0")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: dir.appendingPathComponent("package.json"),
                data: Data(packageJSON(name: "prettier-vscode", version: "10.1.0").utf8)
            )
            builder.addFile(
                at: dir.appendingPathComponent("dist/main.js"),
                data: Data("// prettier".utf8),
                logicalSizeBytes: 12
            )
        }

        let packages = try await makeScanner(roots: [vscodeRoot], provider: provider).scan()

        #expect(packages.count == 1)
        let package = try #require(packages.first)
        #expect(package.manager == .editorExtension)
        #expect(package.id == "editorExtension:\(vscodeRoot.path):prettier-vscode")
        #expect(package.qualifier == vscodeRoot.path)
        #expect(package.name == "prettier-vscode")
        #expect(package.version == "10.1.0")
        #expect(package.installPath == dir)
        #expect(package.isExplicit)
        #expect(!package.isReadOnly)
        #expect((package.sizeBytes ?? 0) > 0)
    }

    @Test("falls back to the directory name when package.json is missing")
    func fromDirectoryNameFallback() async throws {
        let dir = vscodeRoot.appendingPathComponent("ms-python.python-2024.4.1")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: dir)
        }

        let packages = try await makeScanner(roots: [vscodeRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.name == "ms-python.python")
        #expect(package.version == "")
    }

    @Test("tags extensions under the Cursor root with the cursor qualifier")
    func cursorRootQualifier() async throws {
        let dir = cursorRoot.appendingPathComponent("cursor.python-1.0.3")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: dir.appendingPathComponent("package.json"),
                data: Data(packageJSON(name: "python", version: "1.0.3").utf8)
            )
        }

        let packages = try await makeScanner(roots: [cursorRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.qualifier == cursorRoot.path)
        #expect(package.name == "python")
        #expect(package.version == "1.0.3")
    }

    @Test("skips dot-prefixed metadata directories")
    func skipsDotDirectories() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: vscodeRoot.appendingPathComponent("esbenp.prettier-vscode-10.1.0/package.json"),
                data: Data(packageJSON(name: "prettier-vscode", version: "10.1.0").utf8)
            )
            builder.addDirectory(at: vscodeRoot.appendingPathComponent(".obsolete"))
            builder.addDirectory(at: vscodeRoot.appendingPathComponent(".install"))
            builder.addFile(
                at: vscodeRoot.appendingPathComponent(".obsolete/package.json"),
                data: Data(packageJSON(name: "stale", version: "0.0.1").utf8)
            )
        }

        let packages = try await makeScanner(roots: [vscodeRoot], provider: provider).scan()
        #expect(packages.map(\.name) == ["prettier-vscode"])
    }

    @Test("ignores plain files directly inside the extensions root")
    func skipsPlainFiles() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: vscodeRoot.appendingPathComponent("real-ext"))
            builder.addFile(
                at: vscodeRoot.appendingPathComponent("extensions.json"),
                data: Data("{}".utf8),
                logicalSizeBytes: 2
            )
        }

        let packages = try await makeScanner(roots: [vscodeRoot], provider: provider).scan()
        #expect(packages.map(\.name) == ["real-ext"])
    }

    @Test("isAvailable is false when no root exists")
    func availabilityRequiresExistingRoot() async throws {
        let empty = InMemoryDirectoryAccessProvider.make { _ in }
        let scanner = makeScanner(roots: [vscodeRoot], provider: empty)
        #expect(await scanner.isAvailable() == false)

        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: vscodeRoot)
        }
        #expect(await makeScanner(roots: [vscodeRoot], provider: present).isAvailable() == true)
    }

    @Test("discovery finds only the editor extension roots that exist")
    func discoveryFindsExistingRoots() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: home.appendingPathComponent(".vscode/extensions"))
            // .cursor/extensions intentionally absent.
        }

        let roots = EditorExtensionDiscovery.extensionRoots(homeDirectory: home, directoryAccess: provider)

        #expect(roots.map(\.path) == [
            home.appendingPathComponent(".vscode/extensions").path,
        ])
    }
}
