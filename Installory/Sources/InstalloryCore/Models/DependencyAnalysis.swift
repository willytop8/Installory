import Foundation

/// Reverse-dependency analysis for the installed package graph.
///
/// **Limitations (by design):**
/// - Only same-manager, in-inventory direct dependencies are analysed.
///   Cross-manager dependencies (e.g. a Cargo binary calling a Homebrew `ffmpeg`)
///   are invisible.
/// - Managers that do not populate `Package.dependencies` (e.g. `mas`, some
///   `cargo` and `gem` installs) will never produce dependents — this is
///   expected behaviour, not a defect.
/// - "Nothing in your inventory depends on it" ≠ "safe to delete". System-wide
///   usage by other processes, shell scripts, or cross-manager tools is not
///   tracked here.
extension [Package] {

    /// Returns explicitly-installed, non-read-only packages that have no
    /// in-inventory dependents within their own package manager.
    ///
    /// A package qualifies as an orphan candidate when **all** of the following
    /// hold:
    /// - `isExplicit == true`
    /// - `isReadOnly == false`
    /// - it is not denylisted (defaults to `Denylist.default`)
    /// - no other package in the **same manager** lists its name in
    ///   `dependencies` (case-insensitive match)
    ///
    /// The result is sorted by manager raw value, then name, for deterministic
    /// output. The input array is never mutated.
    ///
    /// - Parameter denylist: The denylist to apply; defaults to
    ///   `Denylist.default`. Pass a custom `Denylist` in tests or when the
    ///   caller needs to suppress specific packages.
    /// - Returns: Orphan candidates, sorted manager-then-name.
    public func orphanedPackages(denylist: Denylist = .default) -> [Package] {
        // Build a reverse-dependent index keyed on "manager:lowercased-name".
        // For every package P, each name in P.dependencies gets an entry
        // recording that P depends on it.
        var reverseDependents: [String: Set<String>] = [:]
        for pkg in self {
            for dep in pkg.dependencies {
                let key = reverseKey(manager: pkg.manager, name: dep)
                reverseDependents[key, default: []].insert(pkg.id)
            }
        }

        return self
            .filter { pkg in
                guard pkg.isExplicit else { return false }
                guard !pkg.isReadOnly else { return false }
                guard !denylist.isDenylisted(pkg) else { return false }
                let key = reverseKey(manager: pkg.manager, name: pkg.name)
                // Orphan if reverse-dependent set is absent (no one depends on
                // it at all) or explicitly empty.
                return reverseDependents[key]?.isEmpty ?? true
            }
            .sorted {
                if $0.manager.rawValue != $1.manager.rawValue {
                    return $0.manager.rawValue < $1.manager.rawValue
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    // MARK: - Private

    /// Normalises a (manager, dependency-name) pair into a lookup key.
    /// Name is lowercased so dependency references in `dependencies` arrays
    /// match package names regardless of capitalisation.
    private func reverseKey(manager: PackageManager, name: String) -> String {
        "\(manager.rawValue):\(name.lowercased())"
    }
}
