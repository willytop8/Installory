import Foundation

/// Filters granted URLs down to existing directories, deduplicating by path.
struct ProjectWorkspaceDiscovery {
    static func roots(
        grantedURLs: [URL],
        directoryAccess: any DirectoryAccessProvider
    ) -> [URL] {
        var seen: Set<String> = []
        var roots: [URL] = []
        for granted in grantedURLs {
            let standardized = granted.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            guard directoryAccess.fileExists(at: standardized),
                  let metadata = try? directoryAccess.metadata(at: standardized),
                  metadata.kind == .directory else { continue }
            roots.append(standardized)
        }
        return roots.sorted { $0.path < $1.path }
    }
}

/// Discovers project workspaces under directories the user has granted
/// read access to.
///
/// A workspace is a directory (a granted root itself, or one of its direct
/// children) containing a recognizable marker file: `.git`, `package.json`,
/// `node_modules`, `pyproject.toml`, `requirements.txt`, `Pipfile`, `.venv`,
/// `Cargo.toml`, or a `*.xcodeproj` bundle. Only direct children of each root
/// are inspected, so the walk is shallow, bounded, and read-only. No process
/// is ever executed and nothing outside the granted roots is touched.
///
/// Workspaces are purely informational: the app never removes them.
public struct ProjectWorkspaceScanner: Sendable {
    public struct Limits: Sendable, Equatable {
        public let maximumRoots: Int
        public let maximumDirectoriesPerRoot: Int
        public let maximumWorkspaces: Int

        public init(
            maximumRoots: Int = 64,
            maximumDirectoriesPerRoot: Int = 5_000,
            maximumWorkspaces: Int = 500
        ) {
            self.maximumRoots = maximumRoots
            self.maximumDirectoriesPerRoot = maximumDirectoriesPerRoot
            self.maximumWorkspaces = maximumWorkspaces
        }

        public static let `default` = Limits()
    }

    private let roots: [URL]
    private let directoryAccess: any DirectoryAccessProvider
    private let limits: Limits
    private let directorySizeLimits: DirectorySizeLimits

    /// Discovers and uses every granted directory as a scan root.
    public init(
        grantedURLs: [URL],
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        limits: Limits = .default
    ) {
        self.init(
            roots: ProjectWorkspaceDiscovery.roots(
                grantedURLs: grantedURLs,
                directoryAccess: directoryAccess
            ),
            directoryAccess: directoryAccess,
            limits: limits,
            directorySizeLimits: .default
        )
    }

    /// Uses exactly the given roots (no discovery).
    public init(
        roots: [URL],
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        limits: Limits = .default
    ) {
        self.init(
            roots: roots,
            directoryAccess: directoryAccess,
            limits: limits,
            directorySizeLimits: .default
        )
    }

    init(
        roots: [URL],
        directoryAccess: any DirectoryAccessProvider,
        limits: Limits,
        directorySizeLimits: DirectorySizeLimits
    ) {
        self.roots = roots
        self.directoryAccess = directoryAccess
        self.limits = limits
        self.directorySizeLimits = directorySizeLimits
    }

    public func scan() async throws -> [ProjectWorkspace] {
        try Task.checkCancellation()
        guard roots.count <= limits.maximumRoots else { return [] }

        var workspaces: [ProjectWorkspace] = []
        var seen: Set<String> = []

        for (rootIndex, root) in roots.enumerated() {
            try await checkpoint(rootIndex)
            let rootChildren: [URL]
            do {
                rootChildren = try directoryAccess.contentsOfDirectory(at: root)
            } catch {
                continue
            }
            try Task.checkCancellation()
            guard rootChildren.count <= limits.maximumDirectoriesPerRoot else { continue }

            // The root itself may be a single project (the user granted it
            // directly); otherwise inspect each direct child directory.
            var candidates: [URL] = [root]
            for child in rootChildren.sorted(by: {
                $0.standardizedFileURL.path < $1.standardizedFileURL.path
            }) {
                let standardized = child.standardizedFileURL
                guard let metadata = try? directoryAccess.metadata(at: standardized),
                      metadata.kind == .directory else { continue }
                candidates.append(standardized)
            }

            for (index, candidate) in candidates.enumerated() {
                try await checkpoint(index)
                guard seen.insert(candidate.path).inserted else { continue }
                guard workspaces.count < limits.maximumWorkspaces else {
                    return workspaces
                }
                guard let workspace = try await makeWorkspace(
                    at: candidate,
                    containedIn: root
                ) else { continue }
                workspaces.append(workspace)
            }
        }

        try Task.checkCancellation()
        return workspaces
    }

    private func makeWorkspace(
        at candidate: URL,
        containedIn root: URL
    ) async throws -> ProjectWorkspace? {
        try Task.checkCancellation()
        let resolved = directoryAccess
            .resolvingSymlinks(at: candidate)
            .standardizedFileURL
        guard Self.isContained(resolved, in: root) else { return nil }

        let children: [URL]
        do {
            children = try directoryAccess.contentsOfDirectory(at: candidate)
        } catch {
            return nil
        }
        try Task.checkCancellation()
        guard children.count <= limits.maximumDirectoriesPerRoot else { return nil }

        var kind: ProjectWorkspaceKind?
        var hasGit = false
        var latestModification: Date?

        for child in children {
            try Task.checkCancellation()
            let childURL = child.standardizedFileURL
            let fileName = childURL.lastPathComponent

            if !fileName.hasPrefix("."),
               let mtime = directoryAccess.modificationDate(at: childURL),
               latestModification == nil || mtime > latestModification! {
                latestModification = mtime
            }

            if kind == nil {
                switch fileName {
                case "package.json", "node_modules":
                    kind = .node
                case "pyproject.toml", "requirements.txt", "Pipfile", ".venv":
                    kind = .python
                case "Cargo.toml":
                    kind = .rust
                default:
                    if fileName.hasSuffix(".xcodeproj") {
                        kind = .xcode
                    }
                }
            }
            if fileName == ".git" {
                hasGit = true
            }
        }

        let resolvedKind = kind ?? (hasGit ? .git : nil)
        guard let resolvedKind else { return nil }

        try Task.checkCancellation()
        var sizer = BoundedDirectorySizer(
            directoryAccess: directoryAccess,
            limits: directorySizeLimits
        )
        let measuredSize = try await sizer.measure(
            [.tree(candidate)],
            constrainedTo: root
        ).sizeBytes

        let fallbackMtime = directoryAccess.modificationDate(at: candidate)
        let name = candidate.lastPathComponent.isEmpty
            ? candidate.path
            : candidate.lastPathComponent

        return ProjectWorkspace(
            path: candidate,
            name: name,
            kind: resolvedKind,
            sizeBytes: measuredSize,
            lastModifiedAt: latestModification ?? fallbackMtime
        )
    }

    private func checkpoint(_ index: Int) async throws {
        try Task.checkCancellation()
        if index > 0, index.isMultiple(of: 32) {
            await Task.yield()
            try Task.checkCancellation()
        }
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count >= rootComponents.count
            && candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }
}
