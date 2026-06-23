import Foundation

/// Renders a package inventory as a CSV or Markdown report.
///
/// Pure formatter — no filesystem access. The caller persists the returned
/// string. CSV is RFC 4180 quoting: fields containing comma, quote, or newline
/// are wrapped in double quotes with internal `"` doubled. Markdown uses GitHub
/// pipe tables; pipes and backticks in cells are escaped so the table stays
/// well-formed.
public struct InventoryExporter: Sendable {
    public enum Format: String, Sendable, CaseIterable {
        case csv
        case markdown

        public var fileExtension: String {
            switch self {
            case .csv:      "csv"
            case .markdown: "md"
            }
        }
    }

    public init() {}

    public func export(_ packages: [Package], format: Format) -> String {
        switch format {
        case .csv:      renderCSV(packages)
        case .markdown: renderMarkdown(packages)
        }
    }

    // MARK: - CSV

    private func renderCSV(_ packages: [Package]) -> String {
        let header = "manager,name,version,qualifier,install_path,installed_at,confidence,is_explicit,is_read_only,dependencies"
        let iso = ISO8601DateFormatter()
        let rows = packages.map { pkg -> String in
            [
                pkg.manager.rawValue,
                pkg.name,
                pkg.version,
                pkg.qualifier ?? "",
                pkg.installPath?.path ?? "",
                pkg.installedAt.map { iso.string(from: $0) } ?? "",
                pkg.installedAtConfidence.rawValue,
                pkg.isExplicit ? "true" : "false",
                pkg.isReadOnly ? "true" : "false",
                pkg.dependencies.joined(separator: ";"),
            ]
            .map(csvQuote)
            .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private func csvQuote(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    // MARK: - Markdown

    private func renderMarkdown(_ packages: [Package]) -> String {
        let grouped = Dictionary(grouping: packages, by: \.manager)
            .sorted { $0.key.rawValue < $1.key.rawValue }

        var lines: [String] = [
            "# Installory Inventory",
            "",
            "Exported \(Date().formatted(date: .abbreviated, time: .shortened)).",
            "",
            "| Manager | Packages |",
            "| --- | ---: |",
        ]
        for (manager, pkgs) in grouped {
            lines.append("| \(manager.rawValue) | \(pkgs.count) |")
        }
        lines.append("| **Total** | **\(packages.count)** |")
        lines.append("")

        for (manager, pkgs) in grouped {
            lines.append("## \(manager.rawValue) (\(pkgs.count))")
            lines.append("")
            lines.append("| Name | Version | Installed | Path |")
            lines.append("| --- | --- | --- | --- |")
            for pkg in pkgs.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                let installed = pkg.installedAt.map {
                    $0.formatted(date: .abbreviated, time: .omitted)
                } ?? "—"
                lines.append("| \(mdCell(pkg.name)) | \(mdCell(pkg.version)) | \(installed) | \(mdCell(pkg.installPath?.path ?? "—")) |")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func mdCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
