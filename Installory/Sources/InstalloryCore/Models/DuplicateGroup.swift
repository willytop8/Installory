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
        for (_, pkgs) in byLowercasedName {
            let distinctManagers = Set(pkgs.map { pkg -> PackageManager in
                pkg.manager == .brewCask ? .brew : pkg.manager
            })
            guard distinctManagers.count >= 2, let first = pkgs.first else { continue }
            groups.append(DuplicateGroup(name: first.name, packages: pkgs))
        }

        return groups.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
