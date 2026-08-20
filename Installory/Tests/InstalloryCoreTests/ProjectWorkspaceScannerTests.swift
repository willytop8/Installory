import Foundation
import Testing
@testable import InstalloryCore

@Suite("ProjectWorkspaceScanner")
struct ProjectWorkspaceScannerTests {
    private let root = URL(fileURLWithPath: "/granted/projects", isDirectory: true)

    private func scanner(
        roots: [URL] = [],
        grantedURLs: [URL] = [],
        populate: (inout InMemoryDirectoryAccessProvider.Builder) -> Void
    ) async throws -> [ProjectWorkspace] {
        let access = InMemoryDirectoryAccessProvider.make(populate)
        let scanner: ProjectWorkspaceScanner
        if roots.isEmpty {
            scanner = ProjectWorkspaceScanner(
                grantedURLs: grantedURLs,
                directoryAccess: access
            )
        } else {
            scanner = ProjectWorkspaceScanner(
                roots: roots,
                directoryAccess: access
            )
        }
        return try await scanner.scan()
    }

    @Test func detectsNodeWorkspaceFromPackageJSON() async throws {
        let projects = root
        let app = projects.appendingPathComponent("app-a", isDirectory: true)
        let workspaces = try await scanner(grantedURLs: [projects]) { b in
            b.addFile(at: app.appendingPathComponent("package.json"), data: Data("{}".utf8))
        }
        #expect(workspaces.map(\.name) == ["app-a"])
        #expect(workspaces.first?.kind == .node)
        #expect(workspaces.first?.path == app)
    }

    @Test func detectsPythonWorkspace() async throws {
        let projects = root
        let app = projects.appendingPathComponent("ml", isDirectory: true)
        let workspaces = try await scanner(grantedURLs: [projects]) { b in
            b.addFile(at: app.appendingPathComponent("pyproject.toml"), data: Data())
        }
        #expect(workspaces.first?.kind == .python)
    }

    @Test func detectsRustWorkspace() async throws {
        let projects = root
        let app = projects.appendingPathComponent("cli", isDirectory: true)
        let workspaces = try await scanner(grantedURLs: [projects]) { b in
            b.addFile(at: app.appendingPathComponent("Cargo.toml"), data: Data())
        }
        #expect(workspaces.first?.kind == .rust)
    }

    @Test func detectsXcodeWorkspace() async throws {
        let projects = root
        let app = projects.appendingPathComponent("MyApp", isDirectory: true)
        let workspaces = try await scanner(grantedURLs: [projects]) { b in
            b.addDirectory(at: app.appendingPathComponent("MyApp.xcodeproj", isDirectory: true))
        }
        #expect(workspaces.first?.kind == .xcode)
    }

    @Test func detectsGitOnlyWorkspaceAsGeneric() async throws {
        let projects = root
        let app = projects.appendingPathComponent("notes", isDirectory: true)
        let workspaces = try await scanner(grantedURLs: [projects]) { b in
            b.addDirectory(at: app.appendingPathComponent(".git", isDirectory: true))
        }
        #expect(workspaces.first?.kind == .git)
    }

    @Test func ignoresDirectoryWithoutMarkers() async throws {
        let projects = root
        let empty = projects.appendingPathComponent("empty", isDirectory: true)
        let workspaces = try await scanner(grantedURLs: [projects]) { b in
            b.addDirectory(at: empty)
        }
        #expect(workspaces.isEmpty)
    }

    @Test func treatsGrantedRootAsWorkspaceWhenItHasMarker() async throws {
        let single = URL(fileURLWithPath: "/granted/myapp", isDirectory: true)
        let workspaces = try await scanner(grantedURLs: [single]) { b in
            b.addFile(at: single.appendingPathComponent("package.json"), data: Data("{}".utf8))
        }
        #expect(workspaces.map(\.name) == ["myapp"])
        #expect(workspaces.first?.kind == .node)
    }

    @Test func recordsLastModifiedFromNewestChild() async throws {
        let projects = root
        let app = projects.appendingPathComponent("app-a", isDirectory: true)
        let newer = Date(timeIntervalSince1970: 2_000)
        let older = Date(timeIntervalSince1970: 1_000)
        let workspaces = try await scanner(grantedURLs: [projects]) { b in
            b.addFile(
                at: app.appendingPathComponent("package.json"),
                data: Data(),
                modificationDate: older
            )
            b.addFile(
                at: app.appendingPathComponent("src.swift"),
                data: Data(),
                modificationDate: newer
            )
        }
        #expect(workspaces.first?.lastModifiedAt == newer)
    }

    @Test func measuresSizeOfWorkspaceTree() async throws {
        let projects = root
        let app = projects.appendingPathComponent("app-a", isDirectory: true)
        let workspaces = try await scanner(grantedURLs: [projects]) { b in
            b.addFile(at: app.appendingPathComponent("package.json"), data: Data("{}".utf8))
            b.addFile(
                at: app.appendingPathComponent("index.js"),
                data: Data(repeating: 0x41, count: 1_024)
            )
        }
        #expect(workspaces.first?.sizeBytes == 1_026)
    }
}

@Suite("ProjectWorkspaceAnalysis")
struct ProjectWorkspaceAnalysisTests {
    private func workspace(name: String, lastModified: Date?) -> ProjectWorkspace {
        ProjectWorkspace(
            path: URL(fileURLWithPath: "/granted/\(name)", isDirectory: true),
            name: name,
            kind: .node,
            sizeBytes: nil,
            lastModifiedAt: lastModified
        )
    }

    @Test func sortsStaleFirstWithUnknownLast() {
        let old = workspace(name: "old", lastModified: Date(timeIntervalSince1970: 1_000))
        let new = workspace(name: "new", lastModified: Date(timeIntervalSince1970: 3_000))
        let unknown = workspace(name: "unknown", lastModified: nil)

        let sorted = ProjectWorkspaceAnalysis.sortedByStaleness([new, unknown, old])
        #expect(sorted.map(\.name) == ["old", "new", "unknown"])
    }

    @Test func isStaleUsesThreshold() {
        let now = Date(timeIntervalSince1970: 100_000)
        let fresh = workspace(
            name: "fresh",
            lastModified: Date(timeIntervalSince1970: 99_000)
        )
        let stale = workspace(
            name: "stale",
            lastModified: Date(timeIntervalSince1970: 1_000)
        )
        let threshold: TimeInterval = 50_000
        #expect(!ProjectWorkspaceAnalysis.isStale(fresh, now: now, threshold: threshold))
        #expect(ProjectWorkspaceAnalysis.isStale(stale, now: now, threshold: threshold))
        #expect(!ProjectWorkspaceAnalysis.isStale(
            workspace(name: "x", lastModified: nil),
            now: now,
            threshold: threshold
        ))
    }
}
