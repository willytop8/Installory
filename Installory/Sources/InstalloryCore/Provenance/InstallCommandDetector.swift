import Foundation

/// Parses a single command line and identifies any package-install operations within it.
///
/// Each detected install yields a `(name, manager)` tuple. A single command can yield
/// multiple tuples when several packages are installed in one invocation (e.g.
/// `brew install ffmpeg libpng`).
public struct InstallCommandDetector: Sendable {
    public init() {}

    /// Returns every `(packageName, manager)` pair encoded in `command`.
    ///
    /// Returns an empty array when the command is not a recognised install invocation.
    public func detect(_ command: String) -> [(name: String, manager: PackageManager)] {
        let tokens = command
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        let manager: PackageManager
        let argStartIndex: Int

        switch tokens[0] {
        case "brew":
            guard tokens.count >= 2 else { return [] }
            switch tokens[1] {
            case "install":
                if tokens.count >= 3, tokens[2] == "--cask" {
                    manager = .brewCask
                    argStartIndex = 3
                } else {
                    manager = .brew
                    argStartIndex = 2
                }
            case "reinstall":
                manager = .brew
                argStartIndex = 2
            case "cask":
                guard tokens.count >= 3, tokens[2] == "install" else { return [] }
                manager = .brewCask
                argStartIndex = 3
            default:
                return []
            }
        case "pip", "pip3":
            guard tokens.count >= 2, tokens[1] == "install" else { return [] }
            manager = .pip
            argStartIndex = 2
        case "python", "python3":
            guard tokens.count >= 4,
                  tokens[1] == "-m",
                  tokens[2] == "pip",
                  tokens[3] == "install" else { return [] }
            manager = .pip
            argStartIndex = 4
        case "uv":
            guard tokens.count >= 3, tokens[1] == "pip", tokens[2] == "install" else { return [] }
            manager = .pip
            argStartIndex = 3
        case "pipx":
            guard tokens.count >= 2, tokens[1] == "install" else { return [] }
            manager = .pipx
            argStartIndex = 2
        case "npm":
            guard tokens.count >= 3,
                  tokens[1] == "install" || tokens[1] == "i",
                  let gIdx = tokens.firstIndex(of: "-g"),
                  gIdx >= 2 else { return [] }
            manager = .npm
            argStartIndex = gIdx + 1
        case "yarn":
            guard tokens.count >= 3,
                  tokens[1] == "global",
                  tokens[2] == "add" else { return [] }
            manager = .npm
            argStartIndex = 3
        case "cargo":
            guard tokens.count >= 2, tokens[1] == "install" else { return [] }
            manager = .cargo
            argStartIndex = 2
        case "gem":
            guard tokens.count >= 2, tokens[1] == "install" else { return [] }
            manager = .gem
            argStartIndex = 2
        case "mas":
            guard tokens.count >= 2, tokens[1] == "install" else { return [] }
            manager = .mas
            argStartIndex = 2
        default:
            return []
        }

        return extractPackages(from: Array(tokens[argStartIndex...]), manager: manager)
    }

    // MARK: - Private helpers

    private func extractPackages(
        from args: [String],
        manager: PackageManager
    ) -> [(name: String, manager: PackageManager)] {
        var results: [(name: String, manager: PackageManager)] = []
        var skipNext = false

        for token in args {
            if skipNext {
                skipNext = false
                continue
            }
            // Skip flags; -r skips the following requirement-file argument too.
            if token.hasPrefix("-") {
                if token == "-r" { skipNext = true }
                continue
            }
            // Skip plain requirement-file references (e.g. requirements.txt as positional arg).
            if token.hasSuffix("requirements.txt") { continue }
            // Skip path-like tokens (local wheel files, editable installs, absolute paths).
            if token.contains("/") || token.hasSuffix(".whl") { continue }

            let name = cleaned(token)
            guard !name.isEmpty else { continue }
            results.append((name: name, manager: manager))
        }

        return results
    }

    /// Strips Python extras and version specifiers from a package token.
    ///
    /// `requests[security]` → `requests`
    /// `requests==2.31.0`   → `requests`
    /// `requests>=1.0`      → `requests`
    private func cleaned(_ token: String) -> String {
        var name = token
        // Strip extras bracket: requests[security] → requests
        if let idx = name.firstIndex(of: "[") {
            name = String(name[..<idx])
        }
        // Strip version specifiers (==, !=, >=, <=, ~=, >, <)
        if let idx = name.firstIndex(where: { "=!><~".contains($0) }) {
            name = String(name[..<idx])
        }
        return name
    }
}
