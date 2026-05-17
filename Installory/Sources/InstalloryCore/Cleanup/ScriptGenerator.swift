import Foundation

/// Metadata about the snapshot captured before this cleanup script was generated.
///
/// Pass this to `ScriptGenerator.generate(packages:snapshot:)` so the script
/// header can reference the snapshot the user can restore from if something goes wrong.
public struct SnapshotContext: Sendable {
    public let id: UUID
    public let createdAt: Date

    public init(id: UUID, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

/// The output of `ScriptGenerator.generate(packages:snapshot:)`.
public struct GeneratedScript: Sendable {
    /// Complete shell script text, ready to paste into Terminal.
    public let scriptText: String
    /// Packages omitted because `isReadOnly == true`. Never appear in the script.
    public let skippedReadOnly: [Package]
    /// Packages included in the script as commented-out lines with a warning banner.
    public let warnedDenylisted: [Package]
}

/// Turns a selection of packages into a shell script the user can paste into Terminal.
///
/// This is a pure value: it reads `[Package]` and produces a `GeneratedScript` string.
/// It never touches the filesystem, spawns a process, or accesses the database.
public struct ScriptGenerator: Sendable {
    private let denylist: Denylist

    public init(denylist: Denylist = .default) {
        self.denylist = denylist
    }

    /// Generates a shell script that, when run in Terminal, uninstalls the given packages.
    ///
    /// **Callers MUST capture a snapshot via `SnapshotManager` before calling this method.**
    /// `ScriptGenerator` does not enforce this contract — pass the snapshot metadata via
    /// the `snapshot` parameter so the generated script references it in its header.
    ///
    /// Behaviour:
    /// - Packages with `isReadOnly == true` are excluded and returned in `skippedReadOnly`.
    /// - Denylisted packages are rendered as commented-out lines at the bottom of the script
    ///   and returned in `warnedDenylisted`.
    /// - Within each manager, packages are topologically sorted so dependents are removed
    ///   before their dependencies. Dependency cycles are flagged with a `# WARNING` comment.
    /// Returns the shell command a user would paste into Terminal to remove this single
    /// package, or `nil` when no shell uninstall command exists for it.
    ///
    /// Returns `nil` for:
    /// - packages where `isReadOnly == true` (system packages cannot be removed)
    /// - `.mas` packages (Mac App Store apps have no CLI uninstall)
    ///
    /// This is a pure per-package display API. It performs no denylist filtering,
    /// dependency sorting, or script-header generation. `renderCommand` remains
    /// private and script-oriented; this method owns the nil cases cleanly.
    public func removalCommand(for package: Package) -> String? {
        guard !package.isReadOnly else { return nil }
        switch package.manager {
        case .brew:
            return "brew uninstall \(package.name)"
        case .brewCask:
            return "brew uninstall --cask \(package.name)"
        case .pip:
            let interpreter = package.qualifier ?? "python3"
            let escaped = shellDoubleQuoteEscape(interpreter)
            return "\"\(escaped)\" -m pip uninstall -y \"\(package.name)\""
        case .npm:
            return "npm uninstall -g \"\(package.name)\""
        case .pipx:
            return "pipx uninstall \(package.name)"
        case .cargo:
            return "cargo uninstall \(package.name)"
        case .gem:
            return "gem uninstall \(package.name)"
        case .mas:
            return nil
        }
    }

    public func generate(packages: [Package], snapshot: SnapshotContext? = nil) -> GeneratedScript {
        var skippedReadOnly: [Package] = []
        var warnedDenylisted: [Package] = []
        var active: [Package] = []

        for pkg in packages {
            if pkg.isReadOnly {
                skippedReadOnly.append(pkg)
            } else if denylist.isDenylisted(pkg) {
                warnedDenylisted.append(pkg)
            } else {
                active.append(pkg)
            }
        }

        let script = buildScript(active: active, denylisted: warnedDenylisted, snapshot: snapshot)
        return GeneratedScript(
            scriptText: script,
            skippedReadOnly: skippedReadOnly,
            warnedDenylisted: warnedDenylisted
        )
    }

    // MARK: - Script assembly

    private func buildScript(
        active: [Package],
        denylisted: [Package],
        snapshot: SnapshotContext?
    ) -> String {
        var out: [String] = []
        appendHeader(to: &out, snapshot: snapshot)
        appendManagerSections(packages: active, to: &out)
        if !denylisted.isEmpty {
            appendDenylistSection(packages: denylisted, to: &out)
        }
        return out.joined(separator: "\n") + "\n"
    }

    private func appendHeader(to out: inout [String], snapshot: SnapshotContext?) {
        let fmt = makeISO8601Formatter()
        out.append("#!/bin/bash")
        out.append("# Generated by Installory on \(fmt.string(from: Date()))")
        out.append("# Review every line before running. You can run this script manually")
        out.append("# in Terminal — Installory does not execute it for you.")

        if let snapshot {
            out.append("#")
            out.append("# Snapshot taken before this script was generated:")
            out.append("#   \(snapshot.id.uuidString)  (created \(fmt.string(from: snapshot.createdAt)))")
            out.append("# To restore the original state if something goes wrong, load this")
            out.append("# snapshot in Installory and use \"Restore Missing Packages\".")
        }

        out.append("set -euo pipefail")
    }

    // MARK: - Manager sections

    // Canonical output order. Managers not in this list are appended alphabetically.
    private static let managerOrder: [PackageManager] = [
        .brew, .brewCask, .pip, .npm, .pipx, .cargo, .gem, .mas,
    ]

    private func appendManagerSections(packages: [Package], to out: inout [String]) {
        let handledSet = Set(Self.managerOrder)

        for manager in Self.managerOrder {
            let pkgs = packages.filter { $0.manager == manager }
            guard !pkgs.isEmpty else { continue }
            appendSection(manager: manager, packages: pkgs, to: &out)
        }

        // Managers not in the canonical list (added in future phases)
        let extra = Set(packages.map { $0.manager })
            .subtracting(handledSet)
            .sorted { $0.rawValue < $1.rawValue }
        for manager in extra {
            let pkgs = packages.filter { $0.manager == manager }
            appendSection(manager: manager, packages: pkgs, to: &out)
        }
    }

    private func appendSection(manager: PackageManager, packages: [Package], to out: inout [String]) {
        if manager == .pip {
            // Pip packages are grouped per interpreter; each gets its own sub-section header.
            let byInterpreter = Dictionary(grouping: packages) { $0.qualifier ?? "" }
            for interpreter in byInterpreter.keys.sorted() {
                let pkgs = byInterpreter[interpreter]!
                let sorted = topologicalSort(pkgs)
                out.append("")
                out.append(pipSectionHeader(interpreter: interpreter))
                appendCommandLines(sorted: sorted.sorted, cyclePackages: sorted.cyclePackages, to: &out)
            }
        } else {
            let sorted = topologicalSort(packages)
            out.append("")
            out.append(sectionHeader(for: manager))
            appendCommandLines(sorted: sorted.sorted, cyclePackages: sorted.cyclePackages, to: &out)
        }
    }

    private func appendCommandLines(
        sorted: [Package],
        cyclePackages: [Package],
        to out: inout [String]
    ) {
        for pkg in sorted {
            appendSinglePackageLines(for: pkg, to: &out)
        }
        if !cyclePackages.isEmpty {
            out.append("# WARNING: dependency cycle detected")
            for pkg in cyclePackages {
                appendSinglePackageLines(for: pkg, to: &out)
            }
        }
    }

    private func appendSinglePackageLines(for pkg: Package, to out: inout [String]) {
        if pkg.manager == .mas {
            out.append("# \(pkg.name): mas does not support CLI uninstall; remove the .app manually from /Applications")
            return
        }

        let cmd = renderCommand(for: pkg)
        out.append(shellEchoLine(for: cmd))
        out.append(cmd)

        // For casks, list artifact paths the user may want to clean up manually.
        if pkg.manager == .brewCask, let paths = pkg.artifactPaths, !paths.isEmpty {
            out.append("# Files brew may not remove automatically:")
            for path in paths {
                out.append("#   \(path)")
            }
        }
    }

    private func appendDenylistSection(packages: [Package], to out: inout [String]) {
        let bar = "# " + String(repeating: "=", count: 60)
        out.append("")
        out.append(bar)
        out.append("# WARNING: the following packages are commonly depended on by other")
        out.append("# software. Installory has commented them out. Uncomment only if you are")
        out.append("# certain you do not need them.")
        out.append(bar)

        for pkg in packages {
            let reasonSuffix = denylist.reason(for: pkg).map { "  # reason: \($0)" } ?? ""
            if pkg.manager == .mas {
                out.append("# \(pkg.name): mas does not support CLI uninstall; remove the .app manually from /Applications\(reasonSuffix)")
            } else {
                let cmd = renderCommand(for: pkg)
                out.append("# \(cmd)\(reasonSuffix)")
            }
        }
    }

    // MARK: - Command rendering

    private func renderCommand(for pkg: Package) -> String {
        switch pkg.manager {
        case .brew:
            return "brew uninstall \(pkg.name)"
        case .brewCask:
            return "brew uninstall --cask \(pkg.name)"
        case .pip:
            let interpreter = pkg.qualifier ?? "python3"
            let escaped = shellDoubleQuoteEscape(interpreter)
            return "\"\(escaped)\" -m pip uninstall -y \"\(pkg.name)\""
        case .npm:
            return "npm uninstall -g \"\(pkg.name)\""
        case .pipx:
            return "pipx uninstall \(pkg.name)"
        case .cargo:
            return "cargo uninstall \(pkg.name)"
        case .gem:
            return "gem uninstall \(pkg.name)"
        case .mas:
            // mas has no CLI uninstall; caller handles this case before reaching renderCommand
            return "\(pkg.name)  # remove manually from /Applications"
        }
    }

    private func sectionHeader(for manager: PackageManager) -> String {
        switch manager {
        case .brew:    return "# === Homebrew Formulae ==="
        case .brewCask: return "# === Homebrew Casks ==="
        case .pip:     return "# === pip ==="
        case .npm:     return "# === npm (global) ==="
        case .pipx:    return "# === pipx ==="
        case .cargo:   return "# === Cargo (Rust) ==="
        case .gem:     return "# === Ruby Gems ==="
        case .mas:     return "# === Mac App Store ==="
        }
    }

    private func pipSectionHeader(interpreter: String) -> String {
        interpreter.isEmpty
            ? "# === pip ==="
            : "# === pip (interpreter: \(interpreter)) ==="
    }

    // MARK: - Topological sort

    private struct SortResult: Sendable {
        let sorted: [Package]
        let cyclePackages: [Package]
    }

    /// Kahn's algorithm over the within-group dependency graph.
    ///
    /// Edge A → B means "A depends on B" so A is removed before B in the script.
    /// Nodes with in-degree 0 among the selected set have no selected dependents
    /// and are safe to remove first. Remaining nodes after the traversal form cycles.
    private func topologicalSort(_ packages: [Package]) -> SortResult {
        guard packages.count > 1 else {
            return SortResult(sorted: packages, cyclePackages: [])
        }

        let byName = Dictionary(packages.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        // in-degree: how many selected packages depend on this one
        var inDegree: [String: Int] = Dictionary(uniqueKeysWithValues: packages.map { ($0.name, 0) })
        // adj[x] = dependency names of x that are also in the selected set
        var adj: [String: [String]] = Dictionary(uniqueKeysWithValues: packages.map { ($0.name, []) })

        for pkg in packages {
            for dep in pkg.dependencies where byName[dep] != nil {
                inDegree[dep, default: 0] += 1
                adj[pkg.name, default: []].append(dep)
            }
        }

        for key in adj.keys { adj[key]?.sort() }  // deterministic traversal order

        var queue: [String] = inDegree.filter { $0.value == 0 }.map { $0.key }.sorted()
        var result: [Package] = []
        var seen: Set<String> = []

        while !queue.isEmpty {
            let name = queue.removeFirst()
            guard !seen.contains(name), let pkg = byName[name] else { continue }
            seen.insert(name)
            result.append(pkg)

            for dep in adj[name, default: []] {
                inDegree[dep, default: 0] -= 1
                if inDegree[dep] == 0 {
                    queue.append(dep)
                    queue.sort()
                }
            }
        }

        let cyclePackages = packages.filter { !seen.contains($0.name) }
        return SortResult(sorted: result, cyclePackages: cyclePackages)
    }

    // MARK: - Utilities

    private func makeISO8601Formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }
}
