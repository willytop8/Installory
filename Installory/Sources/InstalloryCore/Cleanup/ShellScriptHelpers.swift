import Foundation

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
