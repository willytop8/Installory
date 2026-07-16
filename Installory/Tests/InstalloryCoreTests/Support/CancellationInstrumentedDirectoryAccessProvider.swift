import Foundation
@testable import InstalloryCore

/// Test-only trace for synchronous directory walks.
///
/// `@unchecked Sendable` is safe here because the lock guards all mutable state.
final class DirectoryEnumerationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPaths: [URL] = []

    var paths: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths
    }

    @discardableResult
    func record(_ url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storedPaths.append(url)
        return storedPaths.count
    }
}

/// Wraps a real in-memory provider and cancels the calling task after a chosen
/// successful directory enumeration. This models cancellation arriving while
/// a scanner is executing a long series of synchronous filesystem calls.
struct CancellationInstrumentedDirectoryAccessProvider: DirectoryAccessProvider, Sendable {
    private let base: any DirectoryAccessProvider
    private let probe: DirectoryEnumerationProbe
    private let cancellationEnumeration: Int

    init(
        base: any DirectoryAccessProvider,
        probe: DirectoryEnumerationProbe,
        cancellationEnumeration: Int
    ) {
        precondition(cancellationEnumeration > 0)
        self.base = base
        self.probe = probe
        self.cancellationEnumeration = cancellationEnumeration
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let contents = try base.contentsOfDirectory(at: url)
        if probe.record(url) == cancellationEnumeration {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        return contents
    }

    func data(contentsOf url: URL) throws -> Data {
        try base.data(contentsOf: url)
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func modificationDate(at url: URL) -> Date? {
        base.modificationDate(at: url)
    }

    func metadata(at url: URL) throws -> FileSystemItemMetadata {
        try base.metadata(at: url)
    }

    func resolvingSymlinks(at url: URL) -> URL {
        base.resolvingSymlinks(at: url)
    }
}
