import Foundation

// MARK: - PathStanding

/// Describes how a specific package stands relative to the system PATH
/// for the name shared across its duplicate group.
///
/// **Design note — sandboxed PATH caveat:**
/// A sandboxed GUI app launched from Finder or Spotlight may have a PATH that
/// differs from the user's interactive login-shell PATH (e.g. ~/.zshrc exports
/// won't be present). PATH is therefore injected as a parameter to every
/// resolver rather than read globally. The UI should present results as
/// "based on this Mac's current PATH" rather than implying certainty about
/// what the user's terminal would see.
public enum PathStanding: Sendable, Equatable {
    /// This package's executable directory appears earliest on PATH;
    /// running the shared command name will invoke this package's binary.
    case wins

    /// Another package in the group appears earlier on PATH.
    /// `byPackageId` is the `Package.id` of the package that wins.
    case shadowed(byPackageId: String)

    /// PATH resolution could not be determined — the executable directory
    /// is not derivable from this package's install layout (e.g. App bundles,
    /// mas) or the derived directory did not appear in `path`.
    case unknown
}

// MARK: - DuplicateSeverity

/// Advisory severity for a cross-manager duplicate group. Used to sort and
/// section the Duplicates view. **Never affects what is removed or pre-selects
/// anything** — it is advisory framing only.
///
/// Declaration order determines `Comparable` ordering: `benign < potential < active`.
public enum DuplicateSeverity: Comparable, Sendable {
    /// Likely harmless — library name collision or only one member is on PATH,
    /// so nothing is actively shadowing anything else.
    case benign

    /// Worth reviewing — the packages look like CLI tools but PATH standing
    /// is unresolved, so we cannot confirm a shadow exists.
    case potential

    /// Real conflict — a winner and at least one shadowed member exist on PATH,
    /// meaning the wrong version of a command could run.
    case active
}

// MARK: - Executable directory derivation

/// Returns the probable binary directory for `package`, or `nil` when the
/// manager's install layout does not place executables on PATH.
///
/// This uses heuristics based on canonical install-path layouts and must be
/// treated as a best-effort estimate. Each manager's expected layout is
/// documented inline.
///
/// - Note: Internal — callers test behaviour through `resolvePathStandings`.
func executableDirectory(for package: Package) -> String? {
    guard let installPath = package.installPath else { return nil }
    let url = installPath

    switch package.manager {
    case .brew:
        // Expected layout: {homebrew-root}/Cellar/{formula-name}/{version}
        // Binary symlinks:  {homebrew-root}/bin/
        // Navigate: version → formula-name → Cellar → homebrew-root → bin
        let root = url
            .deletingLastPathComponent() // formula-name dir
            .deletingLastPathComponent() // Cellar dir
            .deletingLastPathComponent() // homebrew-root
        return root.appendingPathComponent("bin").path

    case .npm:
        // Expected layout: {npm-prefix}/lib/node_modules/{package-name}
        // Binary symlinks:  {npm-prefix}/bin/
        // Navigate: package-name → node_modules → lib → npm-prefix → bin
        let root = url
            .deletingLastPathComponent() // node_modules dir
            .deletingLastPathComponent() // lib dir
            .deletingLastPathComponent() // npm-prefix
        return root.appendingPathComponent("bin").path

    case .cargo:
        // Expected layout: {cargo-home}/bin/{binary-name}
        // installPath points directly at the binary file.
        // If the parent directory is named "bin", that is the executable dir.
        let parent = url.deletingLastPathComponent()
        guard parent.lastPathComponent == "bin" else { return nil }
        return parent.path

    case .pipx:
        // Expected layout: {local-dir}/pipx/venvs/{tool-name}
        // Executable symlinks exposed at: {local-dir}/bin/
        // Navigate: tool-name → venvs → pipx → local-dir → bin
        let localDir = url
            .deletingLastPathComponent() // venvs dir
            .deletingLastPathComponent() // pipx dir
            .deletingLastPathComponent() // local-dir (e.g. ~/.local)
        return localDir.appendingPathComponent("bin").path

    case .gem:
        // Expected layout:
        //   {ruby-root}/lib/ruby/gems/{gemspec-ver}/gems/{gem-name}-{version}
        // Binary dir: {ruby-root}/bin/
        // Navigate up 6 levels:
        //   gem-name-ver → gems dir → gemspec-ver → gems → ruby → lib → ruby-root
        let rubyRoot = url
            .deletingLastPathComponent() // gems dir
            .deletingLastPathComponent() // gemspec-version dir
            .deletingLastPathComponent() // gems dir
            .deletingLastPathComponent() // ruby dir
            .deletingLastPathComponent() // lib dir
            .deletingLastPathComponent() // ruby-root (e.g. ~/.rbenv/versions/3.2.2)
        return rubyRoot.appendingPathComponent("bin").path

    case .pip:
        // pip packages are almost always libraries; executable scripts (when
        // present) live in the interpreter's bin directory, which isn't
        // embedded predictably in installPath. Return nil to stay conservative.
        return nil

    case .brewCask, .mas:
        // App bundles — not resolved via PATH at all.
        return nil
    }
}

// MARK: - PATH resolution

/// Computes the PATH standing of each package in `group`.
///
/// - Parameters:
///   - group: The cross-manager duplicate group to resolve.
///   - path: An ordered list of directories, earliest-searched first, as
///           produced by splitting a PATH string on `":"`. In production, pass
///           `ProcessInfo.processInfo.environment["PATH"]` split on `":"`.
///           Injected so tests can control it precisely and so the UI can
///           add an honest caveat that the value may differ from the terminal's
///           PATH.
/// - Returns: A dictionary mapping `Package.id` to `PathStanding`. Every
///            package in the group is represented. Packages whose executable
///            directory cannot be derived, or whose directory does not appear
///            in `path`, receive `.unknown`.
///
/// **Tie rule:** If two or more packages resolve to the same earliest PATH
/// entry, neither is declared the winner — all tied packages receive
/// `.unknown` (we cannot determine which binary is found first within the
/// same directory).
public func resolvePathStandings(
    for group: DuplicateGroup,
    path: [String]
) -> [String: PathStanding] {
    // Empty PATH → all unknown; avoids index-out-of-bounds and is correct
    // (no resolution possible).
    guard !path.isEmpty else {
        return Dictionary(
            uniqueKeysWithValues: group.packages.map { ($0.id, PathStanding.unknown) }
        )
    }

    // Collect (package, earliest-matching-path-index) pairs.
    typealias Indexed = (package: Package, index: Int)
    var indexed: [Indexed] = []
    for pkg in group.packages {
        guard let dir = executableDirectory(for: pkg) else { continue }
        if let idx = path.firstIndex(of: dir) {
            indexed.append((pkg, idx))
        }
    }

    // Build result dictionary.
    var result: [String: PathStanding] = [:]

    guard !indexed.isEmpty else {
        // No package matched any PATH entry — all unknown.
        for pkg in group.packages { result[pkg.id] = .unknown }
        return result
    }

    let minIndex = indexed.map(\.index).min()!
    let winners = indexed.filter { $0.index == minIndex }
    // Ties at the earliest index: cannot declare a single winner.
    let winnerId: String? = winners.count == 1 ? winners[0].package.id : nil

    for pkg in group.packages {
        if let wid = winnerId, pkg.id == wid {
            result[pkg.id] = .wins
        } else if indexed.contains(where: { $0.package.id == pkg.id }) {
            // Package IS on PATH but later than the winner (or tied).
            if let wid = winnerId {
                result[pkg.id] = .shadowed(byPackageId: wid)
            } else {
                // Tied situation — no single winner to name.
                result[pkg.id] = .unknown
            }
        } else {
            // Not on PATH or executable dir not derivable.
            result[pkg.id] = .unknown
        }
    }

    return result
}

// MARK: - CLI tool heuristic

/// Returns `true` if `package` shows signals of being a command-line tool
/// that would resolve via PATH.
///
/// Conservative by design: when unsure, returns `true` to prefer
/// `.potential` over understating a real conflict as `.benign`.
///
/// Signals used:
/// - `installPath` contains a `/bin/` path component → strong CLI signal.
/// - Manager is `brewCask` or `mas` → app bundles, definitely not CLI.
/// - Manager is `pip` → primarily libraries, no reliable executable signal.
/// - All other managers → assume CLI-capable.
func looksLikeCommandLineTool(_ package: Package) -> Bool {
    // App bundles are unambiguously not on PATH.
    if package.manager == .brewCask || package.manager == .mas { return false }

    if let path = package.installPath?.path {
        // Explicit .app bundle from any manager
        if path.hasSuffix(".app") { return false }
        // A /bin/ component is a clear CLI signal
        if path.contains("/bin/") || path.hasSuffix("/bin") { return true }
    }

    // Manager-level fallback (conservative: treat unknown as CLI-capable).
    switch package.manager {
    case .brew, .cargo, .npm, .pipx, .gem:
        return true
    case .pip:
        return false  // primarily libraries
    case .brewCask, .mas:
        return false  // already handled above, but exhaustive
    }
}

// MARK: - Severity

/// Computes the advisory severity for `group` given pre-computed PATH standings.
///
/// Rules (in priority order):
/// 1. **Active:** a winner AND ≥1 shadowed member exist → real PATH conflict.
/// 2. **Benign:** a winner exists but nothing is shadowed → one member is on
///    PATH, the others are not detected there (nothing is actually overriding
///    anything from a PATH perspective).
/// 3. **Benign:** no package in the group looks like a CLI tool → likely a
///    library name collision with no PATH impact.
/// 4. **Potential:** everything else — CLI-ish tools but PATH is unresolved.
///
/// - Parameters:
///   - group: The duplicate group to evaluate.
///   - standings: As returned by `resolvePathStandings(for:path:)`.
/// - Returns: An advisory `DuplicateSeverity`. Never changes what is removed
///            or pre-selects any action.
public func severity(
    for group: DuplicateGroup,
    standings: [String: PathStanding]
) -> DuplicateSeverity {
    let hasWinner = standings.values.contains(.wins)
    let hasShadowed = standings.values.contains {
        if case .shadowed = $0 { return true }
        return false
    }

    // Active: real shadow detected.
    if hasWinner && hasShadowed { return .active }

    // Winner with no shadow: only one member detected on PATH, so there is
    // no confirmed conflict from a PATH perspective.
    if hasWinner && !hasShadowed { return .benign }

    // No winner (PATH unresolved for all members): check CLI signal.
    let hasCliSignal = group.packages.contains { looksLikeCommandLineTool($0) }
    if !hasCliSignal { return .benign }

    // CLI-ish tools with unresolved PATH → potential conflict.
    return .potential
}
