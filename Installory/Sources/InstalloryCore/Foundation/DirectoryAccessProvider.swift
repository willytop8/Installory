import Foundation

/// Abstracts filesystem directory enumeration and file reading.
///
/// Injected into scanners so tests can supply an in-memory fake without
/// touching the real filesystem or requiring specific on-disk state.
public protocol DirectoryAccessProvider: Sendable {
    /// Returns the direct children of `url`.
    ///
    /// Throws if the directory does not exist or cannot be read.
    func contentsOfDirectory(at url: URL) throws -> [URL]

    /// Returns the raw bytes of the file at `url`.
    ///
    /// Throws if the file does not exist or cannot be read.
    func data(contentsOf url: URL) throws -> Data

    /// Returns true when a regular file or directory exists at `url`.
    func fileExists(at url: URL) -> Bool

    /// Returns the modification date of the item at `url`, or nil if unavailable.
    func modificationDate(at url: URL) -> Date?

    /// Returns `url` with any symlinks in its path resolved to their targets.
    func resolvingSymlinks(at url: URL) -> URL
}

extension DirectoryAccessProvider {
    public func resolvingSymlinks(at url: URL) -> URL {
        url.resolvingSymlinksInPath()
    }
}

/// A `DirectoryAccessProvider` backed by the real filesystem.
public struct SystemDirectoryAccessProvider: DirectoryAccessProvider, Sendable {
    public init() {}

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )
    }

    public func data(contentsOf url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func modificationDate(at url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}
