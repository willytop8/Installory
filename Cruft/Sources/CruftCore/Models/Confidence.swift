/// The strength of evidence behind a derived fact.
///
/// Ordering: `unknown < low < medium < high`.
/// Every field derived from heuristics or inference must carry a `Confidence`
/// so the UI can display it honestly rather than presenting guesses as facts.
public enum Confidence: String, Codable, Sendable {
    case unknown  // no signal at all
    case low      // weak signal, e.g. mtime only
    case medium   // multiple signals with some friction
    case high     // direct evidence, e.g. INSTALL_RECEIPT.json or Claude Code log
}

extension Confidence: Comparable {
    private var sortOrder: Int {
        switch self {
        case .unknown: return 0
        case .low:     return 1
        case .medium:  return 2
        case .high:    return 3
        }
    }

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
