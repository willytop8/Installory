import Foundation

/// A Python interpreter discovered by walking known on-disk installation roots.
public struct PythonInterpreter: Equatable, Hashable, Sendable {
    /// The interpreter executable path.
    public let executable: URL
    /// The parsed interpreter version.
    public let version: PythonVersion
    /// The installation family that owns this interpreter.
    public let kind: Kind
    /// Existing `site-packages` or `dist-packages` directories for this interpreter.
    public let sitePackages: [URL]
    /// True when this interpreter is managed by macOS or Xcode Command Line Tools.
    public let isSystem: Bool

    public init(
        executable: URL,
        version: PythonVersion,
        kind: Kind,
        sitePackages: [URL],
        isSystem: Bool
    ) {
        self.executable = executable
        self.version = version
        self.kind = kind
        self.sitePackages = sitePackages
        self.isSystem = isSystem
    }

    /// The known Python interpreter installation families.
    public enum Kind: String, Codable, Sendable {
        case system
        case commandLineTools
        case homebrew
        case pyenv
        case uv
        case conda
        case pipx
        case projectVenv
    }

    /// A semantic Python version with major, minor, and patch components.
    public struct PythonVersion: Comparable, Codable, Hashable, Sendable {
        public let major: Int
        public let minor: Int
        public let patch: Int

        public init(major: Int, minor: Int, patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        /// Parses a version from strings such as `"3.12"`, `"3.11.7"`, `"Python 3.11.7"`, or `"python@3.12"`.
        /// Requires at least a major.minor pair; bare integers like `"3"` or executable names like `"python3"` return nil.
        public init?(_ string: String) {
            let components = Self.versionComponents(in: string)
            guard components.count >= 2 else { return nil }

            self.major = components[0]
            self.minor = components[1]
            self.patch = components.count >= 3 ? components[2] : 0
        }

        public static func < (lhs: PythonVersion, rhs: PythonVersion) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }

        private static func versionComponents(in string: String) -> [Int] {
            var best: [Int] = []
            var current = ""

            for scalar in string.unicodeScalars {
                if CharacterSet.decimalDigits.contains(scalar) || scalar.value == 46 {
                    current.unicodeScalars.append(scalar)
                } else {
                    best = choose(best: best, candidate: current)
                    current = ""
                }
            }
            return choose(best: best, candidate: current)
        }

        private static func choose(best: [Int], candidate: String) -> [Int] {
            let parts = candidate
                .split(separator: ".")
                .compactMap { Int($0) }
            return parts.count > best.count ? parts : best
        }
    }
}

/// Discovers Python interpreters by walking known filesystem locations.
///
/// Discovery never invokes Python or `pip`; all filesystem operations go
/// through the injected `DirectoryAccessProvider`.
public struct PythonInterpreterDiscovery: Sendable {
    private let directoryAccess: any DirectoryAccessProvider
    private let homeDirectory: URL

    public init(
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) {
        self.directoryAccess = directoryAccess
        self.homeDirectory = homeDirectory
    }

    /// Returns all discovered interpreters from currently supported locations.
    public func discover() -> [PythonInterpreter] {
        let candidates = systemCandidates()
            + commandLineToolsCandidates()
            + homebrewCandidates()
            + pyenvCandidates()
            + uvCandidates()
            + condaCandidates()
            + pipxCandidates()
            + projectVenvCandidates()

        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            guard directoryAccess.fileExists(at: candidate.executable) else { return nil }
            guard seen.insert(candidate.executable.path).inserted else { return nil }
            return makeInterpreter(from: candidate)
        }
        .sorted { $0.executable.path < $1.executable.path }
    }

    // MARK: - Candidate enumeration

    private func systemCandidates() -> [Candidate] {
        [Candidate(
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            kind: .system,
            installRoot: URL(fileURLWithPath: "/usr"),
            versionHint: "python3"
        )]
    }

    private func commandLineToolsCandidates() -> [Candidate] {
        let executable = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/python3")
        return [Candidate(
            executable: executable,
            kind: .commandLineTools,
            installRoot: URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr"),
            versionHint: "python3"
        )]
    }

    private func homebrewCandidates() -> [Candidate] {
        let prefixes = [
            URL(fileURLWithPath: "/opt/homebrew"),
            URL(fileURLWithPath: "/usr/local"),
        ]
        return prefixes.flatMap { prefix in
            homebrewOptCandidates(prefix: prefix)
                + homebrewCellarCandidates(prefix: prefix)
                + homebrewBinCandidates(prefix: prefix)
        }
    }

    private func homebrewOptCandidates(prefix: URL) -> [Candidate] {
        let opt = prefix.appendingPathComponent("opt")
        return childDirectories(of: opt)
            .filter { $0.lastPathComponent.hasPrefix("python@") }
            .flatMap { pythonRoot -> [Candidate] in
                let bin = pythonRoot.appendingPathComponent("bin")
                return pythonExecutables(in: bin).map {
                    Candidate(
                        executable: $0,
                        kind: .homebrew,
                        installRoot: pythonRoot,
                        versionHint: pythonRoot.lastPathComponent
                    )
                }
            }
    }

    private func homebrewCellarCandidates(prefix: URL) -> [Candidate] {
        let cellar = prefix.appendingPathComponent("Cellar")
        return childDirectories(of: cellar)
            .filter { $0.lastPathComponent.hasPrefix("python@") }
            .flatMap { formula -> [Candidate] in
                childDirectories(of: formula).flatMap { versionRoot -> [Candidate] in
                    let bin = versionRoot.appendingPathComponent("bin")
                    return pythonExecutables(in: bin).map {
                        Candidate(
                            executable: $0,
                            kind: .homebrew,
                            installRoot: versionRoot,
                            versionHint: versionRoot.lastPathComponent
                        )
                    }
                }
            }
    }

    private func homebrewBinCandidates(prefix: URL) -> [Candidate] {
        let bin = prefix.appendingPathComponent("bin")
        return pythonExecutables(in: bin).map {
            Candidate(
                executable: $0,
                kind: .homebrew,
                installRoot: prefix,
                versionHint: $0.lastPathComponent
            )
        }
    }

    private func pyenvCandidates() -> [Candidate] {
        let versions = homeDirectory
            .appendingPathComponent(".pyenv")
            .appendingPathComponent("versions")

        return childDirectories(of: versions).map { versionRoot in
            Candidate(
                executable: versionRoot.appendingPathComponent("bin/python"),
                kind: .pyenv,
                installRoot: versionRoot,
                versionHint: versionRoot.lastPathComponent
            )
        }
    }

    private func uvCandidates() -> [Candidate] {
        []
    }

    private func condaCandidates() -> [Candidate] {
        []
    }

    private func pipxCandidates() -> [Candidate] {
        []
    }

    private func projectVenvCandidates() -> [Candidate] {
        []
    }

    // MARK: - Interpreter construction

    private func makeInterpreter(from candidate: Candidate) -> PythonInterpreter? {
        guard let version = inferVersion(from: candidate) else { return nil }

        let sitePackages = [
            candidate.installRoot
                .appendingPathComponent("lib")
                .appendingPathComponent("python\(version.major).\(version.minor)")
                .appendingPathComponent("site-packages"),
            candidate.installRoot
                .appendingPathComponent("lib")
                .appendingPathComponent("python\(version.major).\(version.minor)")
                .appendingPathComponent("dist-packages"),
        ].filter { directoryAccess.fileExists(at: $0) }

        return PythonInterpreter(
            executable: candidate.executable,
            version: version,
            kind: candidate.kind,
            sitePackages: sitePackages,
            isSystem: isSystem(candidate.executable, kind: candidate.kind)
        )
    }

    private func inferVersion(from candidate: Candidate) -> PythonInterpreter.PythonVersion? {
        if let version = PythonInterpreter.PythonVersion(candidate.versionHint) {
            return version
        }

        let lib = candidate.installRoot.appendingPathComponent("lib")
        for child in childDirectories(of: lib) where child.lastPathComponent.hasPrefix("python") {
            if let version = PythonInterpreter.PythonVersion(child.lastPathComponent) {
                return version
            }
        }
        return nil
    }

    private func isSystem(_ executable: URL, kind: PythonInterpreter.Kind) -> Bool {
        kind == .system
            || kind == .commandLineTools
            || executable.path.hasPrefix("/usr/bin")
            || executable.path.contains("CommandLineTools")
    }

    // MARK: - Filesystem helpers

    private func childDirectories(of url: URL) -> [URL] {
        (try? directoryAccess.contentsOfDirectory(at: url)) ?? []
    }

    private func pythonExecutables(in bin: URL) -> [URL] {
        childDirectories(of: bin)
            .filter { child in
                let name = child.lastPathComponent
                if name == "python" || name == "python3" { return true }
                guard name.hasPrefix("python3.") else { return false }
                let suffix = name.dropFirst("python3.".count)
                return !suffix.isEmpty && suffix.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
            }
    }
}

private struct Candidate: Sendable {
    let executable: URL
    let kind: PythonInterpreter.Kind
    let installRoot: URL
    let versionHint: String
}
