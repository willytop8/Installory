import Foundation
@testable import InstalloryCore

enum DirectoryAccessOperation: Sendable, Equatable {
    case contents
    case data
    case exists
    case modificationDate
    case metadata
    case resolvingSymlinks
}

struct DirectoryAccessTraceEntry: Sendable, Equatable {
    let operation: DirectoryAccessOperation
    let url: URL
}

/// Thread-safe because every access to `storedEntries` is guarded by `lock`.
final class DirectoryAccessTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEntries: [DirectoryAccessTraceEntry] = []

    var entries: [DirectoryAccessTraceEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries
    }

    func record(_ operation: DirectoryAccessOperation, at url: URL) {
        lock.lock()
        storedEntries.append(DirectoryAccessTraceEntry(operation: operation, url: url))
        lock.unlock()
    }
}

struct TracingDirectoryAccessProvider: DirectoryAccessProvider, Sendable {
    let base: any DirectoryAccessProvider
    let trace: DirectoryAccessTrace

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        trace.record(.contents, at: url)
        return try base.contentsOfDirectory(at: url)
    }

    func data(contentsOf url: URL) throws -> Data {
        trace.record(.data, at: url)
        return try base.data(contentsOf: url)
    }

    func fileExists(at url: URL) -> Bool {
        trace.record(.exists, at: url)
        return base.fileExists(at: url)
    }

    func modificationDate(at url: URL) -> Date? {
        trace.record(.modificationDate, at: url)
        return base.modificationDate(at: url)
    }

    func metadata(at url: URL) throws -> FileSystemItemMetadata {
        trace.record(.metadata, at: url)
        return try base.metadata(at: url)
    }

    func resolvingSymlinks(at url: URL) -> URL {
        trace.record(.resolvingSymlinks, at: url)
        return base.resolvingSymlinks(at: url)
    }
}
