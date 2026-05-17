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
        requiresDist: [String] = []
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
    }
}

/// Parses Python package metadata from `.dist-info` directories.
public struct DistInfoParser: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case missingMetadata(URL)
        case invalidUTF8(URL)
        case malformedMetadata(line: String)
        case missingRequiredField(String)
    }

    private let directoryAccess: any DirectoryAccessProvider

    public init(directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider()) {
        self.directoryAccess = directoryAccess
    }

    /// Parses `METADATA`, `RECORD`, and optional `INSTALLER` from `directory`.
    public func parse(directory: URL) throws -> DistInfo {
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
            recordPaths: parseRecordIfPresent(in: directory),
            installer: parseInstallerIfPresent(in: directory),
            requiresDist: metadata.requiresDist
        )
    }

    /// Parses a `RECORD` CSV file and returns installed paths.
    public func parseRecord(at url: URL) throws -> [String] {
        let text = try string(contentsOf: url)
        guard !text.isEmpty else { return [] }

        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                splitCSVLine(String(line)).first
            }
            .filter { !$0.isEmpty }
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

    private func parseRecordIfPresent(in directory: URL) -> [String] {
        let url = directory.appendingPathComponent("RECORD")
        return (try? parseRecord(at: url)) ?? []
    }

    private func parseInstallerIfPresent(in directory: URL) -> String? {
        let url = directory.appendingPathComponent("INSTALLER")
        guard let text = try? string(contentsOf: url) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func string(contentsOf url: URL) throws -> String {
        let data = try directoryAccess.data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw Error.invalidUTF8(url)
        }
        return text
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
