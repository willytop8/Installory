import Foundation

/// Reads available shell history files and extracts install commands as
/// ``ProvenanceEvidence/InstallCommandRecord`` values.
///
/// Files are checked in order: `~/.zsh_history`, `~/.bash_history`, and
/// `~/.local/share/fish/fish_history`. Missing or unreadable files are silently
/// skipped — no error is thrown and results from the other shells are still returned.
public struct ShellHistoryCollector: Sendable {
    private let directoryAccess: any DirectoryAccessProvider
    private let homeDirectory: URL

    public init(
        directoryAccess: any DirectoryAccessProvider = SystemDirectoryAccessProvider(),
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) {
        self.directoryAccess = directoryAccess
        self.homeDirectory = homeDirectory
    }

    /// Reads available shell history files and returns every detected install command.
    ///
    /// Skips silently when files are missing or unreadable.
    public func collect() -> [ProvenanceEvidence.InstallCommandRecord] {
        let detector = InstallCommandDetector()
        var records: [ProvenanceEvidence.InstallCommandRecord] = []

        let zshURL = homeDirectory.appendingPathComponent(".zsh_history")
        if let data = try? directoryAccess.data(contentsOf: zshURL) {
            records += parseZshHistory(data, detector: detector)
        }

        let bashURL = homeDirectory.appendingPathComponent(".bash_history")
        if let data = try? directoryAccess.data(contentsOf: bashURL) {
            records += parseBashHistory(data, detector: detector)
        }

        let fishURL = homeDirectory
            .appendingPathComponent(".local")
            .appendingPathComponent("share")
            .appendingPathComponent("fish")
            .appendingPathComponent("fish_history")
        if let data = try? directoryAccess.data(contentsOf: fishURL) {
            records += parseFishHistory(data, detector: detector)
        }

        return records
    }

    // MARK: - Per-shell parsers

    private func parseZshHistory(
        _ data: Data,
        detector: InstallCommandDetector
    ) -> [ProvenanceEvidence.InstallCommandRecord] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let (command, timestamp) = zshLineComponents(line)
            guard !detector.detect(command).isEmpty else { return nil }
            return ProvenanceEvidence.InstallCommandRecord(
                timestamp: timestamp, command: command, shell: .zsh, cwd: nil)
        }
    }

    /// Decomposes one zsh history line into its command string and optional timestamp.
    ///
    /// Extended format: `: <unix_ts>:<elapsed>;<command>`
    /// Bare format: any line that does not start with `: `
    /// Malformed extended header: falls back to nil timestamp; command is still extracted.
    private func zshLineComponents(_ line: String) -> (command: String, timestamp: Date?) {
        guard line.hasPrefix(": ") else { return (line, nil) }
        let rest = String(line.dropFirst(2))
        guard let semiIdx = rest.firstIndex(of: ";") else { return (line, nil) }
        let header = String(rest[..<semiIdx])
        let command = String(rest[rest.index(after: semiIdx)...])
        let tsString = header.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        if let ts = Double(tsString) {
            return (command, Date(timeIntervalSince1970: ts))
        }
        // Malformed header (e.g. `: invalid:0;cmd`) — keep the command, drop the timestamp.
        return (command, nil)
    }

    private func parseBashHistory(
        _ data: Data,
        detector: InstallCommandDetector
    ) -> [ProvenanceEvidence.InstallCommandRecord] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var records: [ProvenanceEvidence.InstallCommandRecord] = []
        var pendingTimestamp: Date? = nil

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                let digits = String(line.dropFirst())
                // A HISTTIMEFORMAT timestamp line is `#` followed only by decimal digits.
                if !digits.isEmpty, digits.allSatisfy(\.isNumber), let ts = Double(digits) {
                    pendingTimestamp = Date(timeIntervalSince1970: ts)
                }
                // Non-numeric comment lines are ignored; they do not clear a pending timestamp.
                continue
            }

            let timestamp = pendingTimestamp
            pendingTimestamp = nil

            guard !detector.detect(line).isEmpty else { continue }
            records.append(ProvenanceEvidence.InstallCommandRecord(
                timestamp: timestamp, command: line, shell: .bash, cwd: nil))
        }

        return records
    }

    private func parseFishHistory(
        _ data: Data,
        detector: InstallCommandDetector
    ) -> [ProvenanceEvidence.InstallCommandRecord] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var records: [ProvenanceEvidence.InstallCommandRecord] = []
        var pendingCmd: String? = nil
        var pendingWhen: Date? = nil

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("- cmd: ") {
                // Flush the previous entry before starting a new one.
                if let cmd = pendingCmd, !detector.detect(cmd).isEmpty {
                    records.append(ProvenanceEvidence.InstallCommandRecord(
                        timestamp: pendingWhen, command: cmd, shell: .fish, cwd: nil))
                }
                pendingCmd = String(line.dropFirst("- cmd: ".count))
                pendingWhen = nil
            } else if line.hasPrefix("  when: ") {
                let rest = String(line.dropFirst("  when: ".count))
                    .trimmingCharacters(in: .whitespaces)
                if let ts = Double(rest) {
                    pendingWhen = Date(timeIntervalSince1970: ts)
                }
            }
            // Other keys (paths:, etc.) are intentionally ignored.
        }

        // Flush the final entry.
        if let cmd = pendingCmd, !detector.detect(cmd).isEmpty {
            records.append(ProvenanceEvidence.InstallCommandRecord(
                timestamp: pendingWhen, command: cmd, shell: .fish, cwd: nil))
        }

        return records
    }
}
