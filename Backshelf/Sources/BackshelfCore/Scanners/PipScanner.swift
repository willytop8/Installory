import Foundation

/// Scans Python packages by walking `*.dist-info` directories inside each
/// interpreter's `site-packages` directories.
///
/// No Python or `pip` invocation is made. All data comes from reading
/// `METADATA`, `RECORD`, and `INSTALLER` files directly.
///
/// Each interpreter's packages are tagged with the interpreter's executable
/// path as `qualifier`, so `requests` installed under pyenv 3.11 and
/// `requests` installed under Homebrew 3.12 are two distinct `Package` rows.
public struct PipScanner: PackageScanner, Sendable {
    public let manager: PackageManager = .pip

    private let discovery: PythonInterpreterDiscovery
    private let parser: DistInfoParser
    private let directoryAccess: any DirectoryAccessProvider

    public init(
        discovery: PythonInterpreterDiscovery = PythonInterpreterDiscovery(),
        parser: DistInfoParser = DistInfoParser(),
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider()
    ) {
        self.discovery = discovery
        self.parser = parser
        self.directoryAccess = directoryAccess
    }

    // MARK: - PackageScanner

    public func isAvailable() async -> Bool {
        !discovery.discover().isEmpty
    }

    public func scan() async throws -> [Package] {
        discovery.discover().flatMap { packagesFor(interpreter: $0) }
    }

    // MARK: - Private

    private func packagesFor(interpreter: PythonInterpreter) -> [Package] {
        interpreter.sitePackages.flatMap { packagesIn(sitePackages: $0, interpreter: interpreter) }
    }

    private func packagesIn(sitePackages: URL, interpreter: PythonInterpreter) -> [Package] {
        let entries = (try? directoryAccess.contentsOfDirectory(at: sitePackages)) ?? []
        return entries
            .filter { $0.lastPathComponent.hasSuffix(".dist-info") }
            .compactMap { makePackage(distInfoDir: $0, interpreter: interpreter) }
    }

    private func makePackage(distInfoDir: URL, interpreter: PythonInterpreter) -> Package? {
        guard let distInfo = try? parser.parse(directory: distInfoDir) else { return nil }

        let executablePath = interpreter.executable.path
        let deps = distInfo.requiresDist.map(Self.barePackageName)

        return Package(
            id: "pip:\(executablePath):\(distInfo.name)",
            manager: .pip,
            qualifier: executablePath,
            name: distInfo.name,
            version: distInfo.version,
            installPath: distInfoDir,
            installedAt: directoryAccess.modificationDate(at: distInfoDir),
            installedAtConfidence: .medium,
            sizeBytes: nil,
            // pip has no installed_on_request equivalent; all packages are treated as explicit.
            isExplicit: true,
            isReadOnly: interpreter.isSystem,
            dependencies: deps,
            lastSeen: Date()
        )
    }

    /// Extracts the bare package name from a `Requires-Dist` value.
    ///
    /// Format: `<name> [(<version_spec>)] [; <env_marker>]`
    /// Returns only `<name>`, stripping all constraints and markers.
    private static func barePackageName(_ requiresDist: String) -> String {
        let trimmed = requiresDist.trimmingCharacters(in: .whitespaces)
        let stopChars = CharacterSet(charactersIn: "(;").union(.whitespaces)
        guard let range = trimmed.rangeOfCharacter(from: stopChars) else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound])
    }
}
