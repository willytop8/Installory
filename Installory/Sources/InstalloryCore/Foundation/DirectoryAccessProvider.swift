import Foundation

public enum FileSystemItemKind: Sendable, Equatable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

public struct FileSystemItemMetadata: Sendable, Equatable {
    public let kind: FileSystemItemKind
    public let logicalSizeBytes: Int64?

    public init(kind: FileSystemItemKind, logicalSizeBytes: Int64? = nil) {
        self.kind = kind
        self.logicalSizeBytes = logicalSizeBytes
    }
}

public enum BoundedReadOrigin: Sendable {
    case prefix
    case suffix
}

public enum DirectoryAccessError: Error, Sendable, Equatable {
    case invalidReadLimit
    case readLimitExceeded(URL)
}

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

    /// Reads at most `maximumBytes`, choosing the beginning or end of a file.
    /// Production uses a seekable file handle so oversized histories are never
    /// loaded whole. Test/fake providers may use the conservative default,
    /// which rejects files whose metadata already exceeds the bound.
    func data(
        contentsOf url: URL,
        maximumBytes: Int,
        from origin: BoundedReadOrigin
    ) throws -> Data

    /// Returns true when a regular file or directory exists at `url`.
    func fileExists(at url: URL) -> Bool

    /// Returns the modification date of the item at `url`, or nil if unavailable.
    func modificationDate(at url: URL) -> Date?

    /// Returns the final item's kind without following a final symbolic link.
    func metadata(at url: URL) throws -> FileSystemItemMetadata

    /// Returns `url` with any symlinks in its path resolved to their targets.
    func resolvingSymlinks(at url: URL) -> URL
}

extension DirectoryAccessProvider {
    public func data(
        contentsOf url: URL,
        maximumBytes: Int,
        from origin: BoundedReadOrigin
    ) throws -> Data {
        guard maximumBytes >= 0 else { throw DirectoryAccessError.invalidReadLimit }
        let item = try metadata(at: url)
        guard item.kind == .regularFile,
              let logicalSizeBytes = item.logicalSizeBytes,
              logicalSizeBytes >= 0,
              logicalSizeBytes <= Int64(maximumBytes) else {
            throw DirectoryAccessError.readLimitExceeded(url)
        }
        let bytes = try data(contentsOf: url)
        guard bytes.count <= maximumBytes else {
            throw DirectoryAccessError.readLimitExceeded(url)
        }
        return bytes
    }

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

    public func data(
        contentsOf url: URL,
        maximumBytes: Int,
        from origin: BoundedReadOrigin
    ) throws -> Data {
        guard maximumBytes >= 0 else { throw DirectoryAccessError.invalidReadLimit }
        try Task.checkCancellation()

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        let limit = UInt64(maximumBytes)
        let offset: UInt64
        switch origin {
        case .prefix:
            offset = 0
        case .suffix:
            offset = length > limit ? length - limit : 0
        }
        try handle.seek(toOffset: offset)
        var bytes = try handle.read(upToCount: maximumBytes) ?? Data()
        if case .suffix = origin, offset > 0 {
            // The seek can land in the middle of a command or JSON record.
            // Discard that partial first line rather than manufacturing evidence.
            if let separator = bytes.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                bytes = Data(bytes[bytes.index(after: separator)...])
            } else {
                bytes = Data()
            }
        }
        try Task.checkCancellation()
        return bytes
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func modificationDate(at url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    public func metadata(at url: URL) throws -> FileSystemItemMetadata {
        let values = try url.resourceValues(forKeys: [
            .isSymbolicLinkKey,
            .isRegularFileKey,
            .isDirectoryKey,
            .totalFileSizeKey,
            .fileSizeKey,
        ])
        if values.isSymbolicLink == true {
            return FileSystemItemMetadata(kind: .symbolicLink)
        }
        if values.isRegularFile == true {
            let size = values.totalFileSize ?? values.fileSize
            return FileSystemItemMetadata(
                kind: .regularFile,
                logicalSizeBytes: size.map(Int64.init)
            )
        }
        if values.isDirectory == true {
            return FileSystemItemMetadata(kind: .directory)
        }
        return FileSystemItemMetadata(kind: .other)
    }
}
