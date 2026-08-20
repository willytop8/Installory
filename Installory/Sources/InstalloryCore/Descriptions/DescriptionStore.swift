import Foundation

/// Read-only lookup store for the bundled package descriptions corpus.
///
/// Load once at startup by passing the URL of `descriptions.json` from the
/// app bundle. The app (not the library) supplies the URL so the library
/// stays testable without referencing `Bundle.main`.
///
/// Lookup normalizes package names before matching — pip names follow PEP 503,
/// npm names are lowercased — so installed names like `requests_oauthlib` or
/// `Requests` find the corpus entry keyed as `pip:requests-oauthlib`.
public struct DescriptionStore: Sendable {

    // MARK: - State

    private let descriptions: [String: String]

    // MARK: - Init

    /// Loads the corpus from a JSON file produced by `scripts/generate-descriptions/generate.py`.
    /// Throws if the file cannot be read or is not valid JSON in the expected format.
    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let corpus = try JSONDecoder().decode(CorpusFile.self, from: data)
        self.descriptions = corpus.descriptions
    }

    /// Empty store — every lookup returns nil. Used as the default when the corpus
    /// file is absent (e.g. in tests that don't load the full bundle).
    public init() {
        self.descriptions = [:]
    }

    /// Internal init for unit tests — accepts the raw keyed dictionary directly.
    init(raw descriptions: [String: String]) {
        self.descriptions = descriptions
    }

    // MARK: - Lookup

    /// Returns the one-line plain-English description for the given package, or
    /// nil if the corpus has no entry for it.
    public func description(for manager: PackageManager, name: String) -> String? {
        descriptions[normalizedKey(manager: manager, name: name)]
    }

    /// Returns the corpus description when available, otherwise a per-manager
    /// plain-English fallback so unknown packages never surface a bare
    /// "no description" state. The fallback describes what the package *is* by
    /// its manager rather than guessing what it does.
    public func descriptionOrFallback(for manager: PackageManager, name: String) -> String {
        description(for: manager, name: name) ?? Self.fallback(for: manager)
    }

    /// A concise, human-friendly one-liner for each manager, used when the
    /// corpus has no entry for a specific package.
    public static func fallback(for manager: PackageManager) -> String {
        switch manager {
        case .brew:
            return "A Homebrew command-line tool."
        case .brewCask:
            return "A Homebrew app installed as a cask."
        case .pip:
            return "A Python package installed with pip."
        case .pipx:
            return "A Python command-line tool installed with pipx."
        case .uv:
            return "A Python tool installed with uv."
        case .npm:
            return "A Node.js package installed with npm."
        case .cargo:
            return "A Rust crate installed with Cargo."
        case .gem:
            return "A Ruby gem."
        case .mas:
            return "An app installed from the Mac App Store."
        case .agentSkill:
            return "An AI agent skill — a folder of instructions and scripts that teaches an agent a new capability."
        case .agentCli:
            return "An AI agent command-line tool, such as Claude Code, Codex, opencode, or Cursor."
        case .editorExtension:
            return "An editor extension for VS Code or Cursor."
        }
    }

    // MARK: - Private

    private func normalizedKey(manager: PackageManager, name: String) -> String {
        let normalizedName: String
        switch manager {
        case .pip, .pipx:
            normalizedName = pep503(name)
        case .uv:
            return "pip:\(pep503(name))"
        case .npm:
            normalizedName = name.lowercased()
        default:
            // brew, brewCask, cargo, gem, mas: exact names from registry
            normalizedName = name
        }
        return "\(manager.rawValue):\(normalizedName)"
    }

    /// PEP 503 normalization: lowercase then collapse runs of [-_.] to a single hyphen.
    private func pep503(_ name: String) -> String {
        var result = ""
        var inSeparator = false
        for ch in name.lowercased() {
            if ch == "-" || ch == "_" || ch == "." {
                if !inSeparator {
                    result.append("-")
                    inSeparator = true
                }
            } else {
                result.append(ch)
                inSeparator = false
            }
        }
        return result
    }

    // MARK: - Private types

    private struct CorpusFile: Decodable {
        let descriptions: [String: String]
    }
}
