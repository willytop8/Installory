import Foundation
@testable import InstalloryCore

/// An in-memory `DirectoryAccessProvider` for use in unit tests.
///
/// Build via `Builder` to populate the fake filesystem, then pass the result
/// to any scanner under test. No real filesystem access is performed.
struct InMemoryDirectoryAccessProvider: DirectoryAccessProvider, Sendable {
    private let contents: [String: [URL]]
    private let fileData: [String: Data]
    private let modificationDates: [String: Date]
    private let symlinks: [String: String]
    private let logicalSizes: [String: Int64]
    private let unreadablePaths: Set<String>

    private init(
        contents: [String: [URL]],
        fileData: [String: Data],
        modificationDates: [String: Date],
        symlinks: [String: String],
        logicalSizes: [String: Int64],
        unreadablePaths: Set<String>
    ) {
        self.contents = contents
        self.fileData = fileData
        self.modificationDates = modificationDates
        self.symlinks = symlinks
        self.logicalSizes = logicalSizes
        self.unreadablePaths = unreadablePaths
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let resolved = resolvingSymlinks(at: url)
        guard !unreadablePaths.contains(resolved.path) else {
            throw CocoaError(.fileReadNoPermission)
        }
        guard let kids = contents[resolved.path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return kids
    }

    func data(contentsOf url: URL) throws -> Data {
        let resolved = resolvingSymlinks(at: url)
        guard !unreadablePaths.contains(resolved.path) else {
            throw CocoaError(.fileReadNoPermission)
        }
        guard let bytes = fileData[resolved.path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return bytes
    }

    func fileExists(at url: URL) -> Bool {
        let resolved = resolvingSymlinks(at: url)
        return contents[resolved.path] != nil || fileData[resolved.path] != nil
    }

    func modificationDate(at url: URL) -> Date? {
        let resolved = resolvingSymlinks(at: url)
        return modificationDates[resolved.path]
    }

    func metadata(at url: URL) throws -> FileSystemItemMetadata {
        let parent = resolvingSymlinks(at: url.deletingLastPathComponent())
        let finalURL = parent.appendingPathComponent(url.lastPathComponent)
        guard !unreadablePaths.contains(finalURL.path) else {
            throw CocoaError(.fileReadNoPermission)
        }
        if symlinks[finalURL.path] != nil {
            return FileSystemItemMetadata(kind: .symbolicLink)
        }
        if let size = logicalSizes[finalURL.path] {
            return FileSystemItemMetadata(kind: .regularFile, logicalSizeBytes: size)
        }
        if contents[finalURL.path] != nil {
            return FileSystemItemMetadata(kind: .directory)
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// Resolves symlinks component-by-component, matching real `FileManager` behaviour.
    ///
    /// Each path component is appended to the in-progress result and checked against
    /// the registered symlinks dictionary. If it is a symlink, the current path is
    /// replaced with the target before the next component is appended. This allows
    /// intermediate directory symlinks to be followed correctly — e.g. a file path
    /// whose parent directory is a symlink resolves to the target directory's subtree.
    func resolvingSymlinks(at url: URL) -> URL {
        let components = url.pathComponents  // includes "/" as the first element
        guard !components.isEmpty else { return url }
        var current = URL(fileURLWithPath: "/")
        for component in components.dropFirst() {
            current = current.appendingPathComponent(component)
            var visited: Set<String> = []
            while let target = symlinks[current.path], visited.insert(current.path).inserted {
                current = URL(fileURLWithPath: target)
            }
        }
        return current
    }

    static func make(_ populate: (inout Builder) -> Void) -> InMemoryDirectoryAccessProvider {
        var builder = Builder()
        populate(&builder)
        return builder.build()
    }
}

// MARK: - Builder

extension InMemoryDirectoryAccessProvider {
    /// Constructs an `InMemoryDirectoryAccessProvider` by registering files.
    ///
    /// Calling `addFile(at:data:)` automatically registers each ancestor
    /// directory so `contentsOfDirectory` works for the full path chain.
    struct Builder {
        private var contents: [String: [URL]] = [:]
        private var fileData: [String: Data] = [:]
        private var modificationDates: [String: Date] = [:]
        private var symlinks: [String: String] = [:]
        private var logicalSizes: [String: Int64] = [:]
        private var unreadablePaths: Set<String> = []

        mutating func addFile(
            at url: URL,
            data: Data,
            modificationDate: Date? = nil,
            logicalSizeBytes: Int64? = nil
        ) {
            fileData[url.path] = data
            logicalSizes[url.path] = logicalSizeBytes ?? Int64(data.count)
            if let date = modificationDate { modificationDates[url.path] = date }
            addToContents(child: url)
        }

        /// Registers a symlink so that `resolvingSymlinks(at:)` and `fileExists(at:)` follow it.
        mutating func addSymlink(at url: URL, target: URL) {
            symlinks[url.path] = target.path
            addToContents(child: url)
        }

        mutating func addDirectory(at url: URL) {
            if contents[url.path] == nil {
                contents[url.path] = []
            }
            addToContents(child: url)
        }

        mutating func makeUnreadable(at url: URL) {
            unreadablePaths.insert(url.path)
        }

        private mutating func addToContents(child: URL) {
            var currentChild = URL(fileURLWithPath: child.standardizedFileURL.path)
            guard var parentPath = Self.parentPath(of: currentChild.path) else { return }

            while true {
                var children = contents[parentPath, default: []]
                if !children.contains(where: { $0.path == currentChild.path }) {
                    children.append(currentChild)
                    contents[parentPath] = children
                }

                guard parentPath != "/" else { return }
                currentChild = URL(fileURLWithPath: parentPath, isDirectory: true)
                guard let nextParent = Self.parentPath(of: parentPath) else { return }
                parentPath = nextParent
            }
        }

        private static func parentPath(of path: String) -> String? {
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            guard !components.isEmpty else { return nil }
            guard components.count > 1 else { return "/" }
            return "/" + components.dropLast().joined(separator: "/")
        }

        func build() -> InMemoryDirectoryAccessProvider {
            InMemoryDirectoryAccessProvider(
                contents: contents,
                fileData: fileData,
                modificationDates: modificationDates,
                symlinks: symlinks,
                logicalSizes: logicalSizes,
                unreadablePaths: unreadablePaths
            )
        }

    }
}
