import Foundation

/// Scans Ruby gems by walking `specifications/*.gemspec` files for common Ruby
/// installations and version managers.
///
/// Gemspecs are not evaluated as Ruby. Installory only uses the filename for
/// name/version and best-effort string extraction for runtime dependencies.
public struct GemScanner: PackageScanner, Sendable {
    public let manager: PackageManager = .gem

    private let directoryAccess: any DirectoryAccessProvider
    private let homeDirectory: URL

    public init(
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.directoryAccess = directoryAccess
        self.homeDirectory = homeDirectory
    }

    public func isAvailable() async -> Bool {
        !specificationDirs().isEmpty
    }

    public var unavailableReason: String {
        "Ruby gem specifications not granted or not found"
    }

    public func scan() async throws -> [Package] {
        var seen: Set<String> = []
        return specificationDirs()
            .flatMap(packagesInSpecificationsDir)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.name, $0.qualifier ?? "") < ($1.name, $1.qualifier ?? "") }
    }

    private func specificationDirs() -> [URL] {
        let roots = rubyGemsRoots()
        var seen: Set<String> = []
        return roots
            .flatMap(specificationDirs(inGemsRoot:))
            .filter { seen.insert(directoryAccess.resolvingSymlinks(at: $0).path).inserted }
            .sorted { $0.path < $1.path }
    }

    private func rubyGemsRoots() -> [URL] {
        var roots: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/lib/ruby/gems"),
            URL(fileURLWithPath: "/usr/local/lib/ruby/gems"),
            URL(fileURLWithPath: "/Library/Ruby/Gems"),
            homeDirectory.appendingPathComponent(".gem/ruby"),
        ]

        let rbenvVersions = homeDirectory.appendingPathComponent(".rbenv/versions")
        roots += childDirectories(of: rbenvVersions)
            .map { $0.appendingPathComponent("lib/ruby/gems") }

        return roots
    }

    private func specificationDirs(inGemsRoot root: URL) -> [URL] {
        var dirs: [URL] = []

        let direct = root.appendingPathComponent("specifications")
        if directoryAccess.fileExists(at: direct) {
            dirs.append(direct)
        }

        for apiVersion in childDirectories(of: root) {
            let specifications = apiVersion.appendingPathComponent("specifications")
            if directoryAccess.fileExists(at: specifications) {
                dirs.append(specifications)
            }
        }

        return dirs
    }

    private func packagesInSpecificationsDir(_ specificationsDir: URL) -> [Package] {
        childDirectories(of: specificationsDir)
            .filter { $0.pathExtension == "gemspec" }
            .compactMap { makePackage(gemspec: $0, specificationsDir: specificationsDir) }
    }

    private func makePackage(gemspec: URL, specificationsDir: URL) -> Package? {
        guard let parsed = parseGemspecFilename(gemspec.lastPathComponent) else { return nil }
        // The unpacked gem directory keeps the platform suffix that `version` drops.
        let gemDirName = [parsed.name, parsed.version, parsed.platform]
            .compactMap { $0 }
            .joined(separator: "-")
        let gemDir = specificationsDir
            .deletingLastPathComponent()
            .appendingPathComponent("gems")
            .appendingPathComponent(gemDirName)
        let installPath = directoryAccess.fileExists(at: gemDir) ? gemDir : gemspec

        return Package(
            id: "gem:\(specificationsDir.path):\(parsed.name)",
            manager: .gem,
            qualifier: specificationsDir.path,
            name: parsed.name,
            version: parsed.version,
            installPath: installPath,
            installedAt: directoryAccess.modificationDate(at: gemspec),
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: isSystemGemPath(specificationsDir),
            dependencies: parseRuntimeDependencies(in: gemspec),
            lastSeen: Date()
        )
    }

    /// Splits `nokogiri-1.15.4-arm64-darwin.gemspec` into name, version, and the
    /// optional platform suffix that binary gems carry.
    ///
    /// The version is the first hyphen-separated segment that is a real gem version;
    /// everything after it is the platform. A backward walk would instead fold the
    /// platform into the version and emit `gem install nokogiri -v 1.15.4-arm64-darwin`,
    /// which fails.
    private func parseGemspecFilename(
        _ filename: String
    ) -> (name: String, version: String, platform: String?)? {
        guard filename.hasSuffix(".gemspec") else { return nil }
        let basename = String(filename.dropLast(".gemspec".count))
        let parts = basename.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        for index in parts.indices.dropFirst() where isGemVersion(parts[index]) {
            let name = parts[..<index].joined(separator: "-")
            guard !name.isEmpty else { return nil }
            let platform = parts[(index + 1)...].joined(separator: "-")
            return (name, String(parts[index]), platform.isEmpty ? nil : platform)
        }

        return nil
    }

    /// A gem version is a dot-separated sequence whose first component is numeric and
    /// whose remaining components are alphanumeric — `1.15.4`, `7.1.0.beta1`, `60`.
    ///
    /// Platform segments never match: `arm64` and `darwin` don't start with a digit,
    /// `x86_64` contains an underscore. Neither does a name segment like `2captcha`,
    /// which is numeric-led but has no dotted structure.
    private func isGemVersion(_ segment: Substring) -> Bool {
        let components = segment.split(separator: ".", omittingEmptySubsequences: false)
        guard let first = components.first, !first.isEmpty,
              first.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) })
        else { return false }

        return components.dropFirst().allSatisfy { component in
            !component.isEmpty
                && component.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
        }
    }

    private func parseRuntimeDependencies(in gemspec: URL) -> [String] {
        guard let data = try? directoryAccess.data(contentsOf: gemspec),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var dependencies: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.contains("add_runtime_dependency") || line.contains("add_dependency") else {
                continue
            }
            if let dependency = firstQuotedString(in: line) {
                dependencies.append(dependency)
            }
        }
        return Array(Set(dependencies)).sorted()
    }

    private func firstQuotedString(in line: String) -> String? {
        for quote in ["\"", "'"] {
            guard let start = line.firstIndex(of: Character(quote)) else { continue }
            let afterStart = line.index(after: start)
            guard let end = line[afterStart...].firstIndex(of: Character(quote)) else { continue }
            let value = String(line[afterStart..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func isSystemGemPath(_ url: URL) -> Bool {
        url.path.hasPrefix("/System/") || url.path.hasPrefix("/Library/Ruby/")
    }

    private func childDirectories(of url: URL) -> [URL] {
        (try? directoryAccess.contentsOfDirectory(at: url)) ?? []
    }
}
