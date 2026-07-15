import Foundation

// MARK: - SnapshotChangeSet (awareness direction)

/// All changes between a snapshot and the current live inventory.
public struct SnapshotChangeSet: Sendable {
    /// Packages present in the live inventory but absent from the snapshot
    /// (installed since the snapshot was taken).
    public let added: [Package]
    /// Packages present in the snapshot but absent from the live inventory
    /// (removed since the snapshot was taken).
    public let removed: [MissingPackage]
    /// Packages present in both the snapshot and live inventory but at
    /// different versions. These are never also in `added` or `removed`.
    public let versionChanged: [VersionChange]

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && versionChanged.isEmpty
    }

    public init(added: [Package], removed: [MissingPackage], versionChanged: [VersionChange]) {
        self.added = added
        self.removed = removed
        self.versionChanged = versionChanged
    }
}

/// A package whose version changed between a snapshot and the live inventory.
public struct VersionChange: Sendable, Identifiable {
    public let name: String
    public let manager: PackageManager
    public let qualifier: String?
    public let oldVersion: String
    public let newVersion: String

    /// Mirrors the `(manager, qualifier, name)` match key.
    public var id: String { "\(manager.rawValue):\(qualifier ?? ""):\(name)" }

    public init(
        name: String,
        manager: PackageManager,
        qualifier: String?,
        oldVersion: String,
        newVersion: String
    ) {
        self.name = name
        self.manager = manager
        self.qualifier = qualifier
        self.oldVersion = oldVersion
        self.newVersion = newVersion
    }
}

/// Returns what changed between a snapshot and the live package inventory.
///
/// Matching is on `(manager, qualifier, name)`, with version added for RubyGems
/// because multiple gem versions can coexist — the same identity used by `snapshotDiff`.
///
/// - **Added**: present in `livePackages` but absent from the snapshot.
/// - **Removed**: present in the snapshot but absent from `livePackages`.
/// - **VersionChanged**: present in both but at different versions.
///   These are never also in `added` or `removed`.
///
/// An empty `SnapshotChangeSet` is a normal outcome — nothing changed.
/// Pure: no I/O, no clock access.
public func snapshotChanges(from snapshot: Snapshot, to livePackages: [Package]) -> SnapshotChangeSet {
    var snapshotByIdentity: [SnapshotIdentity: SnapshotPackage] = [:]
    var snapshotManagerByIdentity: [SnapshotIdentity: PackageManager] = [:]
    for (manager, packages) in snapshot.payload.managers {
        for pkg in packages {
            let identity = SnapshotIdentity(
                manager: manager,
                qualifier: pkg.qualifier,
                name: pkg.name,
                version: pkg.version
            )
            snapshotByIdentity[identity] = pkg
            snapshotManagerByIdentity[identity] = manager
        }
    }

    var liveByIdentity: [SnapshotIdentity: Package] = [:]
    for pkg in livePackages {
        let identity = SnapshotIdentity(
            manager: pkg.manager,
            qualifier: pkg.qualifier,
            name: pkg.name,
            version: pkg.version
        )
        liveByIdentity[identity] = pkg
    }

    let snapshotKeys = Set(snapshotByIdentity.keys)
    let liveKeys = Set(liveByIdentity.keys)

    // Added: in live but not in snapshot
    let added = liveKeys.subtracting(snapshotKeys)
        .compactMap { liveByIdentity[$0] }
        .sorted {
            snapshotIdentityPrecedes(
                manager: $0.manager,
                qualifier: $0.qualifier,
                name: $0.name,
                version: $0.version,
                manager: $1.manager,
                qualifier: $1.qualifier,
                name: $1.name,
                version: $1.version
            )
        }

    // Removed: in snapshot but not in live
    let removed: [MissingPackage] = snapshotKeys.subtracting(liveKeys)
        .compactMap { identity in
            guard let pkg = snapshotByIdentity[identity],
                  let mgr = snapshotManagerByIdentity[identity]
            else { return nil }
            return MissingPackage(manager: mgr, package: pkg)
        }
        .sorted {
            snapshotIdentityPrecedes(
                manager: $0.manager,
                qualifier: $0.package.qualifier,
                name: $0.package.name,
                version: $0.package.version,
                manager: $1.manager,
                qualifier: $1.package.qualifier,
                name: $1.package.name,
                version: $1.package.version
            )
        }

    // VersionChanged: same identity, different version (never in added or removed)
    let versionChanged: [VersionChange] = snapshotKeys.intersection(liveKeys)
        .compactMap { identity in
            guard let snapPkg = snapshotByIdentity[identity],
                  let livePkg = liveByIdentity[identity],
                  snapPkg.version != livePkg.version
            else { return nil }
            return VersionChange(
                name: identity.name,
                manager: identity.manager,
                qualifier: identity.qualifier,
                oldVersion: snapPkg.version,
                newVersion: livePkg.version
            )
        }
        .sorted {
            snapshotIdentityPrecedes(
                manager: $0.manager,
                qualifier: $0.qualifier,
                name: $0.name,
                version: $0.oldVersion,
                manager: $1.manager,
                qualifier: $1.qualifier,
                name: $1.name,
                version: $1.oldVersion
            )
        }

    return SnapshotChangeSet(added: added, removed: removed, versionChanged: versionChanged)
}

// MARK: - MissingPackage (recovery direction)

/// A package that was present in a snapshot but is not in the current live inventory.
public struct MissingPackage: Sendable, Identifiable {
    public let manager: PackageManager
    public let package: SnapshotPackage

    public init(manager: PackageManager, package: SnapshotPackage) {
        self.manager = manager
        self.package = package
    }

    /// Stable identity for `ForEach` keying. Version keeps coexisting RubyGems
    /// installations distinct while remaining harmless for other managers.
    public var id: String {
        "\(manager.rawValue):\(package.qualifier ?? ""):\(package.name):\(package.version)"
    }
}

/// Returns the snapshot entries whose package is not present in the live inventory.
///
/// Matching is on `(manager, qualifier, name)` for managers that replace versions
/// in place. RubyGems also includes version because exact versions can coexist and
/// a snapshot restore must not mistake another installed version for the recorded one.
///
/// An empty result is a normal outcome meaning nothing is missing.
public func snapshotDiff(snapshot: Snapshot, livePackages: [Package]) -> [MissingPackage] {
    let liveSet = Set(livePackages.map {
        SnapshotIdentity(
            manager: $0.manager,
            qualifier: $0.qualifier,
            name: $0.name,
            version: $0.version
        )
    })

    var missing: [MissingPackage] = []
    for (manager, packages) in snapshot.payload.managers {
        for pkg in packages {
            let identity = SnapshotIdentity(
                manager: manager,
                qualifier: pkg.qualifier,
                name: pkg.name,
                version: pkg.version
            )
            if !liveSet.contains(identity) {
                missing.append(MissingPackage(manager: manager, package: pkg))
            }
        }
    }
    return missing.sorted {
        snapshotIdentityPrecedes(
            manager: $0.manager,
            qualifier: $0.package.qualifier,
            name: $0.package.name,
            version: $0.package.version,
            manager: $1.manager,
            qualifier: $1.package.qualifier,
            name: $1.package.name,
            version: $1.package.version
        )
    }
}

/// Most managers treat a version change as one installation changing in place.
/// RubyGems is different: several versions can coexist in one qualifier, so its
/// version participates in snapshot identity and produces add/remove changes.
private struct SnapshotIdentity: Hashable {
    let manager: PackageManager
    let qualifier: String?
    let name: String
    let versionDiscriminator: String?

    init(manager: PackageManager, qualifier: String?, name: String, version: String) {
        self.manager = manager
        self.qualifier = qualifier
        self.name = name
        self.versionDiscriminator = manager == .gem ? version : nil
    }
}

private func snapshotIdentityPrecedes(
    manager lhsManager: PackageManager,
    qualifier lhsQualifier: String?,
    name lhsName: String,
    version lhsVersion: String,
    manager rhsManager: PackageManager,
    qualifier rhsQualifier: String?,
    name rhsName: String,
    version rhsVersion: String
) -> Bool {
    if lhsManager.rawValue != rhsManager.rawValue {
        return lhsManager.rawValue < rhsManager.rawValue
    }
    if lhsQualifier != rhsQualifier {
        return (lhsQualifier ?? "") < (rhsQualifier ?? "")
    }
    if lhsName != rhsName { return lhsName < rhsName }
    return lhsVersion < rhsVersion
}
