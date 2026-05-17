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

    // MARK: - Private

    private func normalizedKey(manager: PackageManager, name: String) -> String {
        let normalizedName: String
        switch manager {
        case .pip, .pipx:
            normalizedName = pep503(name)
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
