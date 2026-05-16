import Foundation
@testable import BackshelfCore

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
        let key = url.path
        guard let kids = contents[key] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return kids
    }

    func data(contentsOf url: URL) throws -> Data {
        let key = url.path
        guard let bytes = fileData[key] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return bytes
    }

    func fileExists(at url: URL) -> Bool {
        let resolved = resolvingSymlinks(at: url)
        return contents[resolved.path] != nil || fileData[resolved.path] != nil
    }

    func modificationDate(at url: URL) -> Date? { modificationDates[url.path] }

    func resolvingSymlinks(at url: URL) -> URL {
        var resolved = url
        var visited: Set<String> = []
        while let target = symlinks[resolved.path], visited.insert(resolved.path).inserted {
            resolved = URL(fileURLWithPath: target)
        }
        return resolved
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
