import Foundation

/// Parsed metadata from a Python `.dist-info` directory.
public struct DistInfo: Equatable, Sendable {
    /// The package name from `METADATA`.
    public let name: String
    /// The package version from `METADATA`.
    public let version: String
    /// The short package summary from `METADATA`, when present.
    public let summary: String?
    /// The package homepage from `METADATA`, when present.
    public let homepage: String?
    /// The package author from `METADATA`, when present.
    public let author: String?
    /// The package license from `METADATA`, when present.
    public let license: String?
    /// The long package description from `METADATA`, when present.
    public let description: String?
    /// Paths listed in `RECORD`.
    public let recordPaths: [String]
    /// The installer tool named by `INSTALLER`, when present.
    public let installer: String?
    /// Whether the `.dist-info` directory contains a `REQUESTED` marker.
    ///
    /// pip writes this marker, which is commonly empty, for requirements the
    /// user requested directly. Its presence matters; its contents do not.
    public let requestedMarkerPresent: Bool
    /// Raw `Requires-Dist` entries from `METADATA`, one per line. Each entry may contain
    /// version constraints and environment markers; callers are responsible for stripping them.
    public let requiresDist: [String]

    public init(
        name: String,
        version: String,
        summary: String?,
        homepage: String?,
        author: String?,
        license: String?,
        description: String?,
        recordPaths: [String],
        installer: String?,
        requiresDist: [String] = [],
        requestedMarkerPresent: Bool = false
    ) {
        self.name = name
        self.version = version
        self.summary = summary
        self.homepage = homepage
        self.author = author
        self.license = license
        self.description = description
        self.recordPaths = recordPaths
        self.installer = installer
        self.requiresDist = requiresDist
        self.requestedMarkerPresent = requestedMarkerPresent
    }
}

/// Parses Python package metadata from `.dist-info` directories.
public struct DistInfoParser: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case missingMetadata(URL)
        case invalidUTF8(URL)
        case malformedMetadata(line: String)
        case missingRequiredField(String)
        case metadataExceedsLimits(URL)
        case recordExceedsLimits(URL)
    }

    private static let maximumMetadataBytes: Int64 = 4 * 1_024 * 1_024
    private static let maximumRecordBytes: Int64 = 16 * 1_024 * 1_024
    private static let maximumRecordEntries = 100_000
    private static let maximumInstallerBytes: Int64 = 4 * 1_024

    private let directoryAccess: any DirectoryAccessProvider

    public init(directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider()) {
        self.directoryAccess = directoryAccess
    }

    /// Parses `METADATA`, `RECORD`, optional `INSTALLER`, and `REQUESTED`
    /// marker presence from `directory`.
    public func parse(directory: URL) throws -> DistInfo {
        let metadata = try parseMetadataOnly(directory: directory)

        return DistInfo(
            name: metadata.name,
            version: metadata.version,
            summary: metadata.summary,
            homepage: metadata.homepage,
            author: metadata.author,
            license: metadata.license,
            description: metadata.description,
            recordPaths: try parseRecordIfPresent(in: directory),
            installer: parseInstallerIfPresent(in: directory),
            requiresDist: metadata.requiresDist,
            requestedMarkerPresent: directoryAccess.fileExists(
                at: directory.appendingPathComponent("REQUESTED")
            )
        )
    }

    /// Parses only `METADATA`. This deliberately never probes `RECORD`,
    /// `INSTALLER`, or `REQUESTED`, for callers such as pipx that discard them.
    public func parseMetadataOnly(directory: URL) throws -> DistInfo {
        let metadataURL = directory.appendingPathComponent("METADATA")
        let metadata = try parseMetadata(at: metadataURL)

        return DistInfo(
            name: metadata.name,
            version: metadata.version,
            summary: metadata.headers["summary"],
            homepage: metadata.headers["home-page"],
            author: metadata.headers["author"],
            license: metadata.headers["license"],
            description: metadata.description,
            recordPaths: [],
            installer: nil,
            requiresDist: metadata.requiresDist,
            requestedMarkerPresent: false
        )
    }

    /// Parses a `RECORD` CSV file and returns installed paths.
    public func parseRecord(at url: URL) throws -> [String] {
        try Task.checkCancellation()
        let metadata = try directoryAccess.metadata(at: url)
        guard metadata.kind == .regularFile,
              let logicalSize = metadata.logicalSizeBytes,
              logicalSize >= 0,
              logicalSize <= Self.maximumRecordBytes else {
            throw Error.recordExceedsLimits(url)
        }

        let data = try directoryAccess.data(contentsOf: url)
        try Task.checkCancellation()
        guard Int64(data.count) <= Self.maximumRecordBytes else {
            throw Error.recordExceedsLimits(url)
        }

        var paths: [String] = []
        var entryCount = 0
        var lineStart = data.startIndex
        var index = lineStart

        while index < data.endIndex {
            let byte = data[index]
            guard byte == 0x0A || byte == 0x0D else {
                index = data.index(after: index)
                continue
            }

            try appendRecordPath(
                from: data[lineStart..<index],
                sourceURL: url,
                paths: &paths,
                entryCount: &entryCount
            )

            let separator = byte
            index = data.index(after: index)
            if separator == 0x0D, index < data.endIndex, data[index] == 0x0A {
                index = data.index(after: index)
            }
            lineStart = index
        }

        try appendRecordPath(
            from: data[lineStart..<data.endIndex],
            sourceURL: url,
            paths: &paths,
            entryCount: &entryCount
        )
        try Task.checkCancellation()
        return paths
    }

    // MARK: - Private

    private func parseMetadata(at url: URL) throws -> Metadata {
        let text: String
        do {
            text = try string(contentsOf: url)
        } catch let parserError as Error {
            throw parserError
        } catch {
            throw Error.missingMetadata(url)
        }

        let (headerText, body) = splitHeadersAndBody(text)
        let headers = try parseHeaders(headerText)
        guard let name = headers["name"], !name.isEmpty else {
            throw Error.missingRequiredField("Name")
        }
        guard let version = headers["version"], !version.isEmpty else {
            throw Error.missingRequiredField("Version")
        }

        let requiresDist = headerText
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let s = String(line)
                let prefix = "requires-dist:"
                guard s.lowercased().hasPrefix(prefix) else { return nil }
                return String(s.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                    .nilIfEmpty
            }

        let blockDescription = body.isEmpty ? nil : body
        let inlineDescription = headers["description"]?.nilIfEmpty

        return Metadata(
            name: name,
            version: version,
            headers: headers,
            description: blockDescription ?? inlineDescription,
            requiresDist: requiresDist
        )
    }

    private func parseHeaders(_ text: String) throws -> [String: String] {
        var headers: [String: String] = [:]
        var currentKey: String?

        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            if rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t") {
                guard let key = currentKey else {
                    throw Error.malformedMetadata(line: rawLine)
                }
                let continuation = rawLine.trimmingCharacters(in: .whitespaces)
                headers[key] = [headers[key], continuation]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                continue
            }

            guard let colonIndex = rawLine.firstIndex(of: ":") else {
                throw Error.malformedMetadata(line: rawLine)
            }

            let key = String(rawLine[..<colonIndex]).lowercased()
            let valueStart = rawLine.index(after: colonIndex)
            let value = String(rawLine[valueStart...])
                .trimmingCharacters(in: .whitespaces)
            headers[key] = value
            currentKey = key
        }

        return headers
    }

    private func splitHeadersAndBody(_ text: String) -> (String, String) {
        if let range = text.range(of: "\r\n\r\n") {
            return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
        }
        if let range = text.range(of: "\n\n") {
            return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
        }
        return (text, "")
    }

    private func parseRecordIfPresent(in directory: URL) throws -> [String] {
        let url = directory.appendingPathComponent("RECORD")
        do {
            return try parseRecord(at: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }
    }

    private func parseInstallerIfPresent(in directory: URL) -> String? {
        let url = directory.appendingPathComponent("INSTALLER")
        guard let metadata = try? directoryAccess.metadata(at: url),
              metadata.kind == .regularFile,
              let logicalSize = metadata.logicalSizeBytes,
              logicalSize >= 0,
              logicalSize <= Self.maximumInstallerBytes,
              let data = try? directoryAccess.data(contentsOf: url),
              Int64(data.count) <= Self.maximumInstallerBytes,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func string(contentsOf url: URL) throws -> String {
        try Task.checkCancellation()
        let item = try directoryAccess.metadata(at: url)
        guard item.kind == .regularFile,
              let logicalSize = item.logicalSizeBytes,
              logicalSize >= 0,
              logicalSize <= Self.maximumMetadataBytes else {
            throw Error.metadataExceedsLimits(url)
        }

        // Read one byte beyond the accepted ceiling. The metadata preflight
        // prevents ordinary oversized loads; the extra byte catches a file that
        // grows between that check and this bounded read.
        let readLimit = Int(Self.maximumMetadataBytes) + 1
        let data = try directoryAccess.data(
            contentsOf: url,
            maximumBytes: readLimit,
            from: .prefix
        )
        try Task.checkCancellation()
        guard Int64(data.count) <= Self.maximumMetadataBytes else {
            throw Error.metadataExceedsLimits(url)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw Error.invalidUTF8(url)
        }
        return text
    }

    private func appendRecordPath(
        from bytes: Data.SubSequence,
        sourceURL: URL,
        paths: inout [String],
        entryCount: inout Int
    ) throws {
        guard !bytes.isEmpty else { return }
        entryCount += 1
        guard entryCount <= Self.maximumRecordEntries else {
            throw Error.recordExceedsLimits(sourceURL)
        }
        if entryCount.isMultiple(of: 256) {
            try Task.checkCancellation()
        }

        guard let line = String(data: Data(bytes), encoding: .utf8) else {
            throw Error.invalidUTF8(sourceURL)
        }
        if let path = splitCSVLine(line).first, !path.isEmpty {
            paths.append(path)
        }
    }

    private func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        if next != "," {
                            field.append(next)
                        } else {
                            fields.append(field)
                            field = ""
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
        }

        fields.append(field)
        return fields
    }
}

private struct Metadata {
    let name: String
    let version: String
    let headers: [String: String]
    let description: String?
    let requiresDist: [String]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
