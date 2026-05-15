import Foundation
@testable import BackshelfCore

/// An in-memory `DirectoryAccessProvider` for use in unit tests.
///
/// Build via `Builder` to populate the fake filesystem, then pass the result
/// to any scanner under test. No real filesystem access is performed.
struct InMemoryDirectoryAccessProvider: DirectoryAccessProvider, Sendable {
    private let contents: [String: [URL]]
    private let fileData: [String: Data]

    private init(contents: [String: [URL]], fileData: [String: Data]) {
        self.contents = contents
        self.fileData = fileData
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
        contents[url.path] != nil || fileData[url.path] != nil
    }

    func modificationDate(at url: URL) -> Date? { nil }

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

        mutating func addFile(at url: URL, data: Data) {
            fileData[url.path] = data
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
            InMemoryDirectoryAccessProvider(contents: contents, fileData: fileData)
        }
    }
}
