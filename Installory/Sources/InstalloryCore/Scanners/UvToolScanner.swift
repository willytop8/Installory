import Foundation

/// Inventories persistent environments created by `uv tool install`.
///
/// The caller selects uv's one authoritative tool root and keeps the covering
/// security-scoped grant active for the lifetime of the scan. The scanner never
/// executes uv or any Python interpreter.
public struct UvToolScanner: PackageScanner, Sendable {
    public struct Limits: Sendable, Equatable {
        public let maximumReceiptBytes: Int
        public let maximumMetadataBytes: Int
        public let maximumToolRootEntries: Int
        public let maximumPythonDirectories: Int
        public let maximumSitePackagesEntries: Int

        public init(
            maximumReceiptBytes: Int = 256 * 1_024,
            maximumMetadataBytes: Int = 4 * 1_024 * 1_024,
            maximumToolRootEntries: Int = 10_000,
            maximumPythonDirectories: Int = 64,
            maximumSitePackagesEntries: Int = 10_000
        ) {
            self.maximumReceiptBytes = maximumReceiptBytes
            self.maximumMetadataBytes = maximumMetadataBytes
            self.maximumToolRootEntries = maximumToolRootEntries
            self.maximumPythonDirectories = maximumPythonDirectories
            self.maximumSitePackagesEntries = maximumSitePackagesEntries
        }

        public static let `default` = Limits()
    }

    public let manager: PackageManager = .uv

    private let toolDirectory: URL
    private let directoryAccess: any DirectoryAccessProvider
    private let parser: DistInfoParser
    private let limits: Limits
    private let directorySizeLimits: DirectorySizeLimits
    private let now: @Sendable () -> Date

    /// Selects uv's authoritative persistent-tool root from the injected
    /// environment, using `$HOME/.local/share/uv/tools` as the final fallback.
    public init(
        homeDirectory: URL,
        environment: PackageManagerEnvironment = .current,
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        parser: DistInfoParser? = nil,
        limits: Limits = .default,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        let fallback = homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("uv", isDirectory: true)
            .appendingPathComponent("tools", isDirectory: true)
        self.init(
            toolDirectory: environment.uvToolDirectory(fallback: fallback),
            directoryAccess: directoryAccess,
            parser: parser,
            limits: limits,
            directorySizeLimits: .default,
            now: now
        )
    }

    public init(
        toolDirectory: URL,
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        parser: DistInfoParser? = nil,
        limits: Limits = .default,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.init(
            toolDirectory: toolDirectory,
            directoryAccess: directoryAccess,
            parser: parser,
            limits: limits,
            directorySizeLimits: .default,
            now: now
        )
    }

    init(
        toolDirectory: URL,
        directoryAccess: any DirectoryAccessProvider,
        parser: DistInfoParser? = nil,
        limits: Limits = .default,
        directorySizeLimits: DirectorySizeLimits,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.toolDirectory = toolDirectory
        self.directoryAccess = directoryAccess
        self.parser = parser ?? DistInfoParser(directoryAccess: directoryAccess)
        self.limits = limits
        self.directorySizeLimits = directorySizeLimits
        self.now = now
    }

    public func isAvailable() async -> Bool {
        guard !Task.isCancelled else { return false }
        let root = resolvedToolDirectory
        guard directoryAccess.fileExists(at: root),
              let metadata = try? directoryAccess.metadata(at: root),
              metadata.kind == .directory else {
            return false
        }
        return !Task.isCancelled
    }

    public var unavailableReason: String {
        "uv tool directory not granted or not found"
    }

    public func scan() async throws -> [Package] {
        try Task.checkCancellation()
        let root = resolvedToolDirectory
        let rootChildren = try directoryAccess.contentsOfDirectory(at: root)
        try Task.checkCancellation()
        guard rootChildren.count <= limits.maximumToolRootEntries else {
            throw UvToolScannerError.structuralLimitExceeded(root)
        }

        let observationDate = now()
        var sizer = BoundedDirectorySizer(
            directoryAccess: directoryAccess,
            limits: directorySizeLimits
        )
        var packages: [Package] = []
        var seenEnvironmentPaths: Set<String> = []

        for (index, child) in rootChildren
            .sorted(by: { $0.standardizedFileURL.path < $1.standardizedFileURL.path })
            .enumerated() {
            try await checkpoint(index)
            let candidate = child.standardizedFileURL
            guard Self.isDirectChild(candidate, of: root) else {
                throw UvToolScannerError.unsafePath(candidate)
            }
            guard !candidate.lastPathComponent.hasPrefix(".tmp") else { continue }

            let metadata = try directoryAccess.metadata(at: candidate)
            try Task.checkCancellation()
            switch metadata.kind {
            case .regularFile, .other:
                // uv may leave marker and lock files beside tool environments.
                continue
            case .symbolicLink:
                throw UvToolScannerError.unsafePath(candidate)
            case .directory:
                let environment = try realDirectory(
                    at: candidate,
                    containedIn: root,
                    directChildOf: root
                )
                guard seenEnvironmentPaths.insert(environment.path).inserted else {
                    throw UvToolScannerError.unsafePath(environment)
                }
                packages.append(
                    try await package(
                        for: environment,
                        in: root,
                        observationDate: observationDate,
                        sizer: &sizer
                    )
                )
            }
        }

        try Task.checkCancellation()
        return packages
    }

    private var resolvedToolDirectory: URL {
        directoryAccess
            .resolvingSymlinks(at: toolDirectory.standardizedFileURL)
            .standardizedFileURL
    }

    private func package(
        for environment: URL,
        in root: URL,
        observationDate: Date,
        sizer: inout BoundedDirectorySizer
    ) async throws -> Package {
        try Task.checkCancellation()
        guard let target = Self.normalizedDistributionName(environment.lastPathComponent) else {
            throw UvToolScannerError.invalidToolName(environment)
        }

        let receiptURL = environment.appendingPathComponent("uv-receipt.toml")
        let receiptData = try boundedRegularFile(
            at: receiptURL,
            maximumBytes: limits.maximumReceiptBytes,
            oversizedError: .receiptExceedsLimit(receiptURL),
            containedIn: root
        )
        try Task.checkCancellation()

        let receipt: UvToolReceipt
        do {
            receipt = try UvToolReceiptParser().parse(receiptData)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UvToolScannerError.invalidReceipt(receiptURL)
        }
        try Task.checkCancellation()

        if let receiptName = receipt.primaryRequirementName {
            guard let normalizedReceiptName = Self.normalizedDistributionName(receiptName),
                  normalizedReceiptName == target else {
                throw UvToolScannerError.primaryRequirementMismatch(environment)
            }
        }

        let matches = try await matchingDistributions(
            in: environment,
            root: root,
            target: target
        )
        guard let selected = matches.first else {
            throw UvToolScannerError.missingTargetDistribution(environment)
        }
        guard matches.count == 1 else {
            throw UvToolScannerError.ambiguousTargetDistribution(environment)
        }

        let artifactPaths = try receipt.entrypoints
            .map { try Self.validatedAbsolutePath($0.installPath, receiptURL: receiptURL) }
            .uniquedAndSorted()
        let measuredSize = try await sizer.measure(
            [.tree(environment)],
            constrainedTo: root
        ).sizeBytes
        try Task.checkCancellation()

        return Package(
            id: "uv:\(environment.path):\(target)",
            manager: .uv,
            qualifier: environment.path,
            name: selected.info.name,
            version: selected.info.version,
            installPath: environment,
            installedAt: directoryAccess.modificationDate(at: selected.directory)
                ?? directoryAccess.modificationDate(at: receiptURL),
            installedAtConfidence: .medium,
            sizeBytes: measuredSize,
            isExplicit: true,
            isReadOnly: false,
            dependencies: selected.info.requiresDist.map(PythonRequirement.distributionName),
            artifactPaths: artifactPaths.isEmpty ? nil : artifactPaths,
            lastSeen: observationDate
        )
    }

    private func matchingDistributions(
        in environment: URL,
        root: URL,
        target: String
    ) async throws -> [(directory: URL, info: DistInfo)] {
        let lib = try realDirectory(
            at: environment.appendingPathComponent("lib", isDirectory: true),
            containedIn: root
        )
        try Task.checkCancellation()
        let libChildren = try directoryAccess.contentsOfDirectory(at: lib)
        try Task.checkCancellation()
        guard libChildren.count <= limits.maximumSitePackagesEntries else {
            throw UvToolScannerError.structuralLimitExceeded(lib)
        }

        let pythonCandidates = libChildren
            .filter { $0.lastPathComponent.hasPrefix("python") }
            .sorted(by: { $0.standardizedFileURL.path < $1.standardizedFileURL.path })
        guard pythonCandidates.count <= limits.maximumPythonDirectories else {
            throw UvToolScannerError.structuralLimitExceeded(lib)
        }

        var matches: [(directory: URL, info: DistInfo)] = []
        var sitePackagesEntryCount = 0

        for (pythonIndex, candidate) in pythonCandidates.enumerated() {
            try await checkpoint(pythonIndex)
            let pythonDirectory = try realDirectory(
                at: candidate,
                containedIn: root,
                directChildOf: lib
            )
            let sitePackagesURL = pythonDirectory
                .appendingPathComponent("site-packages", isDirectory: true)
            guard directoryAccess.fileExists(at: sitePackagesURL) else { continue }
            let sitePackages = try realDirectory(at: sitePackagesURL, containedIn: root)

            try Task.checkCancellation()
            let entries = try directoryAccess.contentsOfDirectory(at: sitePackages)
                .sorted(by: { $0.standardizedFileURL.path < $1.standardizedFileURL.path })
            try Task.checkCancellation()
            let (nextCount, overflow) = sitePackagesEntryCount
                .addingReportingOverflow(entries.count)
            guard !overflow, nextCount <= limits.maximumSitePackagesEntries else {
                throw UvToolScannerError.structuralLimitExceeded(sitePackages)
            }
            sitePackagesEntryCount = nextCount

            for (entryIndex, entry) in entries.enumerated() {
                try await checkpoint(entryIndex)
                guard entry.lastPathComponent.hasSuffix(".dist-info") else { continue }
                let distInfoDirectory = try realDirectory(
                    at: entry,
                    containedIn: root,
                    directChildOf: sitePackages
                )
                try validateMetadataFile(
                    at: distInfoDirectory.appendingPathComponent("METADATA"),
                    containedIn: root
                )
                try Task.checkCancellation()
                let info = try parser.parseMetadataOnly(directory: distInfoDirectory)
                try Task.checkCancellation()
                guard let normalizedName = Self.normalizedDistributionName(info.name) else {
                    throw UvToolScannerError.invalidDistributionName(distInfoDirectory)
                }
                if normalizedName == target {
                    matches.append((distInfoDirectory, info))
                    if matches.count > 1 {
                        throw UvToolScannerError.ambiguousTargetDistribution(environment)
                    }
                }
            }
        }

        try Task.checkCancellation()
        return matches
    }

    private func validateMetadataFile(at url: URL, containedIn root: URL) throws {
        try Task.checkCancellation()
        let standardized = url.standardizedFileURL
        let resolved = directoryAccess
            .resolvingSymlinks(at: standardized)
            .standardizedFileURL
        guard Self.isContained(resolved, in: root) else {
            throw UvToolScannerError.unsafePath(standardized)
        }
        let metadata = try directoryAccess.metadata(at: standardized)
        guard metadata.kind == .regularFile,
              let size = metadata.logicalSizeBytes,
              size >= 0,
              limits.maximumMetadataBytes >= 0,
              size <= Int64(limits.maximumMetadataBytes) else {
            throw UvToolScannerError.metadataExceedsLimit(standardized)
        }
        try Task.checkCancellation()
    }

    private func boundedRegularFile(
        at url: URL,
        maximumBytes: Int,
        oversizedError: UvToolScannerError,
        containedIn root: URL
    ) throws -> Data {
        try Task.checkCancellation()
        let standardized = url.standardizedFileURL
        let resolved = directoryAccess
            .resolvingSymlinks(at: standardized)
            .standardizedFileURL
        guard Self.isContained(resolved, in: root) else {
            throw UvToolScannerError.unsafePath(standardized)
        }

        let metadata = try directoryAccess.metadata(at: standardized)
        guard metadata.kind == .regularFile,
              let logicalSize = metadata.logicalSizeBytes,
              logicalSize >= 0,
              maximumBytes >= 0,
              logicalSize <= Int64(maximumBytes) else {
            throw oversizedError
        }

        let data: Data
        do {
            data = try directoryAccess.data(
                contentsOf: standardized,
                maximumBytes: maximumBytes,
                from: .prefix
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw oversizedError
        }
        try Task.checkCancellation()
        guard data.count <= maximumBytes, Int64(data.count) == logicalSize else {
            throw oversizedError
        }
        return data
    }

    private func realDirectory(
        at url: URL,
        containedIn root: URL,
        directChildOf expectedParent: URL? = nil
    ) throws -> URL {
        try Task.checkCancellation()
        let standardized = url.standardizedFileURL
        if let expectedParent,
           !Self.isDirectChild(standardized, of: expectedParent.standardizedFileURL) {
            throw UvToolScannerError.unsafePath(standardized)
        }

        let metadata = try directoryAccess.metadata(at: standardized)
        guard metadata.kind == .directory else {
            throw UvToolScannerError.unsafePath(standardized)
        }
        let resolved = directoryAccess
            .resolvingSymlinks(at: standardized)
            .standardizedFileURL
        guard Self.isContained(resolved, in: root) else {
            throw UvToolScannerError.unsafePath(standardized)
        }
        if let expectedParent,
           !Self.isDirectChild(resolved, of: expectedParent.standardizedFileURL) {
            throw UvToolScannerError.unsafePath(standardized)
        }
        return resolved
    }

    private func checkpoint(_ index: Int) async throws {
        try Task.checkCancellation()
        if index > 0, index.isMultiple(of: 32) {
            await Task.yield()
            try Task.checkCancellation()
        }
    }

    private static func normalizedDistributionName(_ rawName: String) -> String? {
        let scalars = Array(rawName.unicodeScalars)
        guard let first = scalars.first, let last = scalars.last,
              isASCIIAlphanumeric(first), isASCIIAlphanumeric(last) else {
            return nil
        }

        var normalized = ""
        var previousWasSeparator = false
        for scalar in scalars {
            if isASCIIAlphanumeric(scalar) {
                normalized.unicodeScalars.append(
                    scalar.value >= 65 && scalar.value <= 90
                        ? UnicodeScalar(scalar.value + 32)!
                        : scalar
                )
                previousWasSeparator = false
            } else if scalar == "-" || scalar == "_" || scalar == "." {
                if !previousWasSeparator {
                    normalized.append("-")
                    previousWasSeparator = true
                }
            } else {
                return nil
            }
        }
        return normalized
    }

    private static func isASCIIAlphanumeric(_ scalar: UnicodeScalar) -> Bool {
        (scalar.value >= 48 && scalar.value <= 57)
            || (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func validatedAbsolutePath(
        _ rawPath: String,
        receiptURL: URL
    ) throws -> String {
        guard rawPath.hasPrefix("/"), rawPath != "/",
              !rawPath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw UvToolScannerError.invalidEntrypointPath(receiptURL)
        }
        let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        guard standardized.hasPrefix("/"), standardized != "/" else {
            throw UvToolScannerError.invalidEntrypointPath(receiptURL)
        }
        return standardized
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count >= rootComponents.count
            && candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }

    private static func isDirectChild(_ candidate: URL, of parent: URL) -> Bool {
        candidate.standardizedFileURL.deletingLastPathComponent().standardizedFileURL.path
            == parent.standardizedFileURL.path
    }
}

enum UvToolScannerError: Swift.Error, Equatable, Sendable {
    case unsafePath(URL)
    case invalidToolName(URL)
    case invalidDistributionName(URL)
    case invalidReceipt(URL)
    case receiptExceedsLimit(URL)
    case metadataExceedsLimit(URL)
    case structuralLimitExceeded(URL)
    case primaryRequirementMismatch(URL)
    case missingTargetDistribution(URL)
    case ambiguousTargetDistribution(URL)
    case invalidEntrypointPath(URL)
}

private struct UvToolReceipt: Sendable {
    let primaryRequirementName: String?
    let entrypoints: [Entrypoint]

    struct Entrypoint: Sendable {
        let name: String
        let installPath: String
        let from: String?
    }
}

private struct UvToolReceiptParser {
    private enum ParseError: Swift.Error {
        case malformed
    }

    func parse(_ data: Data) throws -> UvToolReceipt {
        try Task.checkCancellation()
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParseError.malformed
        }
        let section = try toolSection(in: text)
        guard let requirementsValue = try arrayAssignment(named: "requirements", in: section),
              let entrypointsValue = try arrayAssignment(named: "entrypoints", in: section) else {
            throw ParseError.malformed
        }

        let requirements = try splitTopLevelArray(requirementsValue)
        guard let firstRequirement = requirements.first else {
            throw ParseError.malformed
        }
        let primaryName = try requirementName(from: firstRequirement)

        let entrypoints = try splitTopLevelArray(entrypointsValue).map { value in
            let table = try inlineTable(value)
            guard let rawName = table["name"],
                  let rawInstallPath = table["install-path"] else {
                throw ParseError.malformed
            }
            let name = try decodedString(rawName)
            let installPath = try decodedString(rawInstallPath)
            let from = try table["from"].map(decodedString)
            guard !name.isEmpty,
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  from?.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) != true else {
                throw ParseError.malformed
            }
            return UvToolReceipt.Entrypoint(
                name: name,
                installPath: installPath,
                from: from
            )
        }
        try Task.checkCancellation()
        return UvToolReceipt(
            primaryRequirementName: primaryName,
            entrypoints: entrypoints
        )
    }

    private func toolSection(in text: String) throws -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var foundTool = false
        var sectionLines: [String] = []

        for (index, rawLine) in lines.enumerated() {
            if index.isMultiple(of: 32) { try Task.checkCancellation() }
            let line = String(rawLine)
            let token = withoutComment(line)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if token.hasPrefix("[") {
                if token == "[tool]" {
                    guard !foundTool else { throw ParseError.malformed }
                    foundTool = true
                    continue
                }
                if foundTool { break }
            }
            if foundTool { sectionLines.append(line) }
        }
        guard foundTool else { throw ParseError.malformed }
        return sectionLines.joined(separator: "\n")
    }

    private func arrayAssignment(named key: String, in section: String) throws -> String? {
        let lines = section.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var matchIndex: Int?
        var firstRemainder = ""

        for (index, line) in lines.enumerated() {
            if index.isMultiple(of: 32) { try Task.checkCancellation() }
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            guard trimmed.hasPrefix(key) else { continue }
            let afterKey = trimmed.dropFirst(key.count)
            guard afterKey.first == nil || afterKey.first == " "
                    || afterKey.first == "\t" || afterKey.first == "=" else {
                continue
            }
            let afterWhitespace = afterKey.drop(while: { $0 == " " || $0 == "\t" })
            guard afterWhitespace.first == "=" else { continue }
            guard matchIndex == nil else { throw ParseError.malformed }
            matchIndex = index
            firstRemainder = String(afterWhitespace.dropFirst())
        }

        guard let matchIndex else { return nil }
        let candidate = ([firstRemainder] + Array(lines.dropFirst(matchIndex + 1)))
            .joined(separator: "\n")
        return try balancedArrayPrefix(in: candidate)
    }

    private func balancedArrayPrefix(in source: String) throws -> String {
        let characters = Array(source)
        var start: Int?
        var squareDepth = 0
        var braceDepth = 0
        var quote: Character?
        var escaped = false
        var inComment = false

        for (index, character) in characters.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            if inComment {
                if character == "\n" { inComment = false }
                continue
            }
            if let activeQuote = quote {
                if activeQuote == "\"", escaped {
                    escaped = false
                } else if activeQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                continue
            }
            if character == "#" {
                inComment = true
                continue
            }
            if character == "\"" || character == "'" {
                guard start != nil else { throw ParseError.malformed }
                quote = character
                continue
            }
            if start == nil {
                if character.isWhitespace { continue }
                guard character == "[" else { throw ParseError.malformed }
                start = index
                squareDepth = 1
                continue
            }

            switch character {
            case "[": squareDepth += 1
            case "]": squareDepth -= 1
            case "{": braceDepth += 1
            case "}": braceDepth -= 1
            default: break
            }
            guard squareDepth >= 0, braceDepth >= 0 else {
                throw ParseError.malformed
            }
            if squareDepth == 0, braceDepth == 0, let start {
                return String(characters[start...index])
            }
        }
        throw ParseError.malformed
    }

    private func splitTopLevelArray(_ value: String) throws -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "[", trimmed.last == "]" else {
            throw ParseError.malformed
        }
        return try splitTopLevel(String(trimmed.dropFirst().dropLast()))
    }

    private func splitTopLevel(_ source: String) throws -> [String] {
        let characters = Array(source)
        var values: [String] = []
        var current: [Character] = []
        var squareDepth = 0
        var braceDepth = 0
        var quote: Character?
        var escaped = false
        var inComment = false

        for (index, character) in characters.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            if inComment {
                if character == "\n" {
                    inComment = false
                    current.append(character)
                }
                continue
            }
            if let activeQuote = quote {
                current.append(character)
                if activeQuote == "\"", escaped {
                    escaped = false
                } else if activeQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                continue
            }
            if character == "#" {
                inComment = true
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                continue
            }
            switch character {
            case "[": squareDepth += 1
            case "]": squareDepth -= 1
            case "{": braceDepth += 1
            case "}": braceDepth -= 1
            case "," where squareDepth == 0 && braceDepth == 0:
                let value = String(current).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { values.append(value) }
                current.removeAll(keepingCapacity: true)
                continue
            default: break
            }
            guard squareDepth >= 0, braceDepth >= 0 else {
                throw ParseError.malformed
            }
            current.append(character)
        }
        guard quote == nil, !inComment, squareDepth == 0, braceDepth == 0 else {
            throw ParseError.malformed
        }
        let final = String(current).trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty { values.append(final) }
        return values
    }

    private func requirementName(from value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" {
            let table = try inlineTable(trimmed)
            guard let rawName = table["name"] else { throw ParseError.malformed }
            return try decodedString(rawName)
        }

        let requirement = try decodedString(trimmed)
        let stopCharacters = CharacterSet(charactersIn: "[<>=!~@;")
            .union(.whitespacesAndNewlines)
        let name: String
        if let stop = requirement.rangeOfCharacter(from: stopCharacters) {
            name = String(requirement[..<stop.lowerBound])
        } else {
            name = requirement
        }
        guard !name.isEmpty else { throw ParseError.malformed }
        return name
    }

    private func inlineTable(_ value: String) throws -> [String: String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else {
            throw ParseError.malformed
        }
        var result: [String: String] = [:]
        for field in try splitTopLevel(String(trimmed.dropFirst().dropLast())) {
            let (rawKey, rawValue) = try splitAssignment(field)
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, result[key] == nil else { throw ParseError.malformed }
            result[key] = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func splitAssignment(_ field: String) throws -> (String, String) {
        let characters = Array(field)
        var quote: Character?
        var escaped = false
        var squareDepth = 0
        var braceDepth = 0

        for (index, character) in characters.enumerated() {
            if let activeQuote = quote {
                if activeQuote == "\"", escaped {
                    escaped = false
                } else if activeQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            switch character {
            case "[": squareDepth += 1
            case "]": squareDepth -= 1
            case "{": braceDepth += 1
            case "}": braceDepth -= 1
            case "=" where squareDepth == 0 && braceDepth == 0:
                return (
                    String(characters[..<index]),
                    String(characters[(index + 1)...])
                )
            default: break
            }
        }
        throw ParseError.malformed
    }

    private func decodedString(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(trimmed)
        guard let delimiter = characters.first,
              delimiter == "\"" || delimiter == "'",
              characters.count >= 2 else {
            throw ParseError.malformed
        }

        var output = ""
        var index = 1
        while index < characters.count {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let character = characters[index]
            if character == delimiter {
                guard index == characters.count - 1 else { throw ParseError.malformed }
                return output
            }
            if delimiter == "'" {
                guard !character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw ParseError.malformed
                }
                output.append(character)
                index += 1
                continue
            }
            guard character == "\\" else {
                guard !character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw ParseError.malformed
                }
                output.append(character)
                index += 1
                continue
            }

            index += 1
            guard index < characters.count else { throw ParseError.malformed }
            let escape = characters[index]
            switch escape {
            case "b": output.append("\u{0008}")
            case "t": output.append("\t")
            case "n": output.append("\n")
            case "f": output.append("\u{000C}")
            case "r": output.append("\r")
            case "e": output.append("\u{001B}")
            case "\"": output.append("\"")
            case "\\": output.append("\\")
            case "u", "U":
                let count = escape == "u" ? 4 : 8
                let start = index + 1
                let end = start + count
                guard end <= characters.count else { throw ParseError.malformed }
                let hexadecimal = String(characters[start..<end])
                guard let value = UInt32(hexadecimal, radix: 16),
                      let scalar = UnicodeScalar(value) else {
                    throw ParseError.malformed
                }
                output.unicodeScalars.append(scalar)
                index = end - 1
            default:
                throw ParseError.malformed
            }
            index += 1
        }
        throw ParseError.malformed
    }

    private func withoutComment(_ line: String) -> String {
        var output = ""
        var quote: Character?
        var escaped = false
        for character in line {
            if let activeQuote = quote {
                output.append(character)
                if activeQuote == "\"", escaped {
                    escaped = false
                } else if activeQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
                output.append(character)
            } else if character == "#" {
                break
            } else {
                output.append(character)
            }
        }
        return output
    }
}

private extension Array where Element == String {
    func uniquedAndSorted() -> [String] {
        Array(Set(self)).sorted()
    }
}
