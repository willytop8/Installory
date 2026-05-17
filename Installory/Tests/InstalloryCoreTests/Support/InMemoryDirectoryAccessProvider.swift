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

    private init(
        contents: [String: [URL]],
        fileData: [String: Data],
        modificationDates: [String: Date],
        symlinks: [String: String]
    ) {
        self.contents = contents
        self.fileData = fileData
        self.modificationDates = modificationDates
        self.symlinks = symlinks
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let resolved = resolvingSymlinks(at: url)
        guard let kids = contents[resolved.path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return kids
    }

    func data(contentsOf url: URL) throws -> Data {
        let resolved = resolvingSymlinks(at: url)
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

        mutating func addFile(at url: URL, data: Data, modificationDate: Date? = nil) {
            fileData[url.path] = data
            if let date = modificationDate { modificationDates[url.path] = date }
            addToContents(child: url, parent: url.deletingLastPathComponent())
        }

        /// Registers a symlink so that `resolvingSymlinks(at:)` and `fileExists(at:)` follow it.
        mutating func addSymlink(at url: URL, target: URL) {
            symlinks[url.path] = target.path
            addToContents(child: url, parent: url.deletingLastPathComponent())
        }

        private mutating func addToContents(child: URL, parent: URL) {
            let parentPath = parent.path
            if contents[parentPath] == nil {
                contents[parentPath] = []
            }
            if !contents[parentPath]!.contains(child) {
                contents[parentPath]!.append(child)
            }
            let grandparent = parent.deletingLastPathComponent()
            if grandparent.path != parent.path {
                addToContents(child: parent, parent: grandparent)
            }
        }

        func build() -> InMemoryDirectoryAccessProvider {
            InMemoryDirectoryAccessProvider(
                contents: contents,
                fileData: fileData,
                modificationDates: modificationDates,
                symlinks: symlinks
            )
        }
    }
}
