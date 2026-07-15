import Foundation

enum PythonRequirement {
    /// Extracts the distribution name from a raw `Requires-Dist` value while
    /// preserving extras as part of the name, matching existing scanner output.
    static func distributionName(from requiresDist: String) -> String {
        let trimmed = requiresDist.trimmingCharacters(in: .whitespaces)
        let stopCharacters = CharacterSet(charactersIn: "(;").union(.whitespaces)
        guard let range = trimmed.rangeOfCharacter(from: stopCharacters) else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound])
    }
}
