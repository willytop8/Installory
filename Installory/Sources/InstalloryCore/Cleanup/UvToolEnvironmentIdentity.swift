import Foundation

/// A validated uv tool environment and the exact root/name pair needed for
/// `uv tool uninstall`. This is intentionally derived only from the scanner's
/// absolute environment qualifier; package display names are never command targets.
enum UvToolEnvironmentIdentity {
    struct Target: Sendable, Equatable {
        let toolsRoot: String
        let environmentName: String
    }

    static func target(from qualifier: String?) -> Target? {
        guard let qualifier,
              !qualifier.isEmpty,
              qualifier == qualifier.trimmingCharacters(in: .whitespacesAndNewlines),
              qualifier.hasPrefix("/"),
              !qualifier.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }

        let rawComponents = qualifier.split(separator: "/", omittingEmptySubsequences: true)
        guard !rawComponents.isEmpty,
              !rawComponents.contains(where: { $0 == "." || $0 == ".." }) else {
            return nil
        }

        let environment = URL(fileURLWithPath: qualifier, isDirectory: true)
            .standardizedFileURL
        let environmentName = environment.lastPathComponent
        guard !environmentName.isEmpty,
              isValidEnvironmentName(environmentName),
              environment.path != "/" else {
            return nil
        }

        let toolsRoot = environment.deletingLastPathComponent().standardizedFileURL
        guard toolsRoot.path != "/", toolsRoot.path != environment.path else { return nil }
        return Target(toolsRoot: toolsRoot.path, environmentName: environmentName)
    }

    private static func isValidEnvironmentName(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard let first = scalars.first, let last = scalars.last,
              isASCIIAlphanumeric(first), isASCIIAlphanumeric(last) else {
            return false
        }
        return scalars.allSatisfy { scalar in
            isASCIIAlphanumeric(scalar) || scalar == "-" || scalar == "_" || scalar == "."
        }
    }

    private static func isASCIIAlphanumeric(_ scalar: UnicodeScalar) -> Bool {
        (scalar.value >= 48 && scalar.value <= 57)
            || (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }
}
