import Foundation

/// A set of packages that share the same name (case-insensitive) across two or more
/// distinct package managers. Brew and brewCask are treated as the same manager.
public struct DuplicateGroup: Sendable {
    public let name: String
    public let packages: [Package]

    public init(name: String, packages: [Package]) {
        self.name = name
        self.packages = packages
    }
}

// MARK: - MultiLocationGroup

/// A set of packages from the **same** manager that share the same name
/// (case-insensitive) but are installed under two or more distinct,
/// non-nil qualifiers (e.g. different pip interpreters, different rbenv
/// Ruby versions).
///
/// This is informational only: same-manager installs in multiple environments
/// are usually fine, but can cause confusion when different tools silently
/// pick different installs.
public struct MultiLocationGroup: Identifiable, Sendable {
    public let manager: PackageManager
    public let name: String
    public let packages: [Package]

    /// Stable SwiftUI identity across managers that happen to contain the same name.
    public var id: String { "\(manager.rawValue)::\(name.lowercased())" }

    public init(manager: PackageManager, name: String, packages: [Package]) {
        self.manager = manager
        self.name = name
        self.packages = packages
    }
}

extension [Package] {
    /// Returns groups of packages whose names match (case-insensitively) across two or
    /// more distinct package managers, sorted by name.
    ///
    /// Brew and brewCask count as one manager — a formula and a cask of the same name
    /// are not a cross-manager duplicate. Multiple pip installs of the same package
    /// across different interpreters are also one manager and do not qualify.
    public func crossManagerDuplicates() -> [DuplicateGroup] {
        var byLowercasedName: [String: [Package]] = [:]
        for pkg in self {
            byLowercasedName[pkg.name.lowercased(), default: []].append(pkg)
        }

        var groups: [DuplicateGroup] = []
        for normalizedName in byLowercasedName.keys.sorted() {
            guard let unorderedPackages = byLowercasedName[normalizedName] else { continue }
            let packages = unorderedPackages.sorted { $0.id < $1.id }
            let distinctManagers = Set(packages.map { pkg -> PackageManager in
                pkg.manager == .brewCask ? .brew : pkg.manager
            })
            guard distinctManagers.count >= 2, let first = packages.first else { continue }
            groups.append(DuplicateGroup(name: first.name, packages: packages))
        }

        return groups
    }

    /// Returns packages that are installed under two or more distinct, non-nil
    /// qualifiers within the **same** package manager, sorted by manager then name.
    ///
    /// Use this to surface "same package installed in multiple Python environments"
    /// or "same gem in multiple Ruby versions" situations — informational, not alarming.
    ///
    /// Managers excluded because they have no meaningful scope qualifier:
    /// - `.brew` and `.brewCask` — Homebrew uses a single global Cellar.
    /// - `.mas` — Mac App Store uses bundle IDs as qualifier (not scope-based).
    ///
    /// A package with a `nil` qualifier does not count toward the distinct-qualifier
    /// threshold but IS included in the resulting group when a group is emitted.
    public func multiLocationInstalls() -> [MultiLocationGroup] {
        // Managers whose qualifier represents meaningful scope separation.
        let excluded: Set<PackageManager> = [.brew, .brewCask, .mas]

        // Group by (manager, lowercased-name).
        var byKey: [String: (manager: PackageManager, name: String, packages: [Package])] = [:]
        for pkg in self {
            guard !excluded.contains(pkg.manager) else { continue }
            let key = "\(pkg.manager.rawValue)::\(pkg.name.lowercased())"
            if byKey[key] == nil {
                byKey[key] = (pkg.manager, pkg.name, [pkg])
            } else {
                byKey[key]!.packages.append(pkg)
            }
        }

        var groups: [MultiLocationGroup] = []
        for key in byKey.keys.sorted() {
            guard let entry = byKey[key] else { continue }
            // Emit a group only when ≥2 distinct non-nil qualifiers exist.
            let distinctQualifiers = Set(entry.packages.compactMap { $0.qualifier })
            guard distinctQualifiers.count >= 2 else { continue }
            let packages = entry.packages.sorted { $0.id < $1.id }
            groups.append(
                MultiLocationGroup(
                    manager: entry.manager,
                    name: packages.first?.name ?? entry.name,
                    packages: packages
                )
            )
        }

        // Sort: manager name alphabetically, then package name alphabetically.
        return groups.sorted {
            if $0.manager.rawValue != $1.manager.rawValue {
                return $0.manager.rawValue < $1.manager.rawValue
            }
            let lhsName = $0.name.lowercased()
            let rhsName = $1.name.lowercased()
            if lhsName != rhsName { return lhsName < rhsName }
            return $0.id < $1.id
        }
    }
}
