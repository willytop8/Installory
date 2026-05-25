import Foundation

/// Quotes one value as a single shell argument.
func shellArgument(_ s: String) -> String {
    guard !s.isEmpty else { return "''" }
    let safeScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
    if s.unicodeScalars.allSatisfy({ safeScalars.contains($0) }) {
        return s
    }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Escapes characters that are special inside bash double-quoted strings.
func shellDoubleQuoteEscape(_ s: String) -> String {
    s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "$", with: "\\$")
}

/// Wraps `cmd` in a bash `echo` line, escaping characters special inside double quotes.
func shellEchoLine(for cmd: String) -> String {
    let escaped = shellDoubleQuoteEscape(cmd)
    return "echo \"→ \(escaped)\""
}
