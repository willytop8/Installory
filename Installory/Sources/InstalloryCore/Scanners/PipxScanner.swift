import Foundation

/// Scans pipx-managed command-line tools by reading each venv under
/// `~/.local/share/pipx/venvs`.
///
/// pipx keeps one tool per virtual environment. Installory reports the main
/// package for each venv, not every dependency inside that venv.
public struct PipxScanner: PackageScanner, Sendable {
    public let manager: PackageManager = .pipx

    private let directoryAccess: any DirectoryAccessProvider
    private let parser: DistInfoParser
    private let homeDirectory: URL

    public init(
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        parser: DistInfoParser? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.directoryAccess = directoryAccess
        self.parser = parser ?? DistInfoParser(directoryAccess: directoryAccess)
        self.homeDirectory = homeDirectory
    }

    public func isAvailable() async -> Bool {
        directoryAccess.fileExists(at: venvsRoot)
    }

    public var unavailableReason: String {
        "pipx venv directory not granted or not found"
    }

    public func scan() async throws -> [Package] {
        childDirectories(of: venvsRoot)
            .sorted { $0.path < $1.path }
            .compactMap(packageForToolVenv)
    }

    private var venvsRoot: URL {
        homeDirectory
            .appendingPathComponent(".local")
            .appendingPathComponent("share")
            .appendingPathComponent("pipx")
            .appendingPathComponent("venvs")
    }

    private func packageForToolVenv(_ venvDir: URL) -> Package? {
        let toolName = venvDir.lastPathComponent
        guard !toolName.hasPrefix(".") else { return nil }

        let distInfos = sitePackagesDirs(in: venvDir)
            .flatMap(parsedDistInfos(in:))
        guard !distInfos.isEmpty else { return nil }

        let metadata = pipxMetadata(in: venvDir)
        let selected = selectMainPackage(
            from: distInfos,
            toolName: toolName,
            metadataName: metadata?.packageName
        )

        if let selected {
            return makePackage(
                name: selected.info.name,
                version: selected.info.version,
                dependencies: selected.info.requiresDist.map(Self.barePackageName),
                distInfoDir: selected.directory,
                venvDir: venvDir
            )
        }

        guard let metadata, let packageName = metadata.packageName, let version = metadata.packageVersion else {
            return nil
        }

        return makePackage(
            name: packageName,
            version: version,
            dependencies: [],
            distInfoDir: nil,
            venvDir: venvDir
        )
    }

    private func sitePackagesDirs(in venvDir: URL) -> [URL] {
        let lib = venvDir.appendingPathComponent("lib")
        return childDirectories(of: lib)
            .filter { $0.lastPathComponent.hasPrefix("python") }
            .map { $0.appendingPathComponent("site-packages") }
            .filter { directoryAccess.fileExists(at: $0) }
    }

    private func parsedDistInfos(in sitePackages: URL) -> [(directory: URL, info: DistInfo)] {
        childDirectories(of: sitePackages)
            .filter { $0.lastPathComponent.hasSuffix(".dist-info") }
            .compactMap { directory in
                guard let info = try? parser.parse(directory: directory) else { return nil }
                return (directory, info)
            }
    }

    private func selectMainPackage(
        from distInfos: [(directory: URL, info: DistInfo)],
        toolName: String,
        metadataName: String?
    ) -> (directory: URL, info: DistInfo)? {
        if let metadataName {
            let normalized = Self.normalizePackageName(metadataName)
            if let match = distInfos.first(where: { Self.normalizePackageName($0.info.name) == normalized }) {
                return match
            }
        }

        let normalizedTool = Self.normalizePackageName(toolName)
        if let match = distInfos.first(where: { Self.normalizePackageName($0.info.name) == normalizedTool }) {
            return match
        }

        return distInfos.count == 1 ? distInfos[0] : nil
    }

    private func makePackage(
        name: String,
        version: String,
        dependencies: [String],
        distInfoDir: URL?,
        venvDir: URL
    ) -> Package {
        Package(
            id: "pipx::\(name)",
            manager: .pipx,
            qualifier: nil,
            name: name,
            version: version,
            installPath: venvDir,
            installedAt: directoryAccess.modificationDate(at: distInfoDir ?? venvDir),
            installedAtConfidence: .medium,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: dependencies,
            lastSeen: Date()
        )
    }

    private func pipxMetadata(in venvDir: URL) -> PipxMetadata? {
        let url = venvDir.appendingPathComponent("pipx_metadata.json")
        guard let data = try? directoryAccess.data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PipxMetadata.self, from: data)
    }

    private func childDirectories(of url: URL) -> [URL] {
        (try? directoryAccess.contentsOfDirectory(at: url)) ?? []
    }

    private static func normalizePackageName(_ name: String) -> String {
        var out = ""
        var previousWasSeparator = false
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                out.append("-")
                previousWasSeparator = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func barePackageName(_ requiresDist: String) -> String {
        let trimmed = requiresDist.trimmingCharacters(in: .whitespaces)
        let stopChars = CharacterSet(charactersIn: "(;").union(.whitespaces)
        guard let range = trimmed.rangeOfCharacter(from: stopChars) else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound])
    }
}

private struct PipxMetadata: Decodable, Sendable {
    let mainPackage: MainPackage?

    var packageName: String? {
        mainPackage?.package?.nilIfBlank ?? mainPackage?.packageOrURL?.nilIfBlank
    }

    var packageVersion: String? {
        mainPackage?.packageVersion?.nilIfBlank
    }

    enum CodingKeys: String, CodingKey {
        case mainPackage = "main_package"
    }

    struct MainPackage: Decodable, Sendable {
        let package: String?
        let packageOrURL: String?
        let packageVersion: String?

        enum CodingKeys: String, CodingKey {
            case package
            case packageOrURL = "package_or_url"
            case packageVersion = "package_version"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
