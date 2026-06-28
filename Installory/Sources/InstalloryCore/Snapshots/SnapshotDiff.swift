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
/// Matching is on `(manager, qualifier, name)` — the same identity key used by `snapshotDiff`.
///
/// - **Added**: present in `livePackages` but absent from the snapshot.
/// - **Removed**: present in the snapshot but absent from `livePackages`.
/// - **VersionChanged**: present in both but at different versions.
///   These are never also in `added` or `removed`.
///
/// An empty `SnapshotChangeSet` is a normal outcome — nothing changed.
/// Pure: no I/O, no clock access.
public func snapshotChanges(from snapshot: Snapshot, to livePackages: [Package]) -> SnapshotChangeSet {
    struct Identity: Hashable {
        let manager: PackageManager
        let qualifier: String?
        let name: String
    }

    var snapshotByIdentity: [Identity: SnapshotPackage] = [:]
    var snapshotManagerByIdentity: [Identity: PackageManager] = [:]
    for (manager, packages) in snapshot.payload.managers {
        for pkg in packages {
            let identity = Identity(manager: manager, qualifier: pkg.qualifier, name: pkg.name)
            snapshotByIdentity[identity] = pkg
            snapshotManagerByIdentity[identity] = manager
        }
    }

    var liveByIdentity: [Identity: Package] = [:]
    for pkg in livePackages {
        let identity = Identity(manager: pkg.manager, qualifier: pkg.qualifier, name: pkg.name)
        liveByIdentity[identity] = pkg
    }

    let snapshotKeys = Set(snapshotByIdentity.keys)
    let liveKeys = Set(liveByIdentity.keys)

    // Added: in live but not in snapshot
    let added = liveKeys.subtracting(snapshotKeys).compactMap { liveByIdentity[$0] }

    // Removed: in snapshot but not in live
    let removed: [MissingPackage] = snapshotKeys.subtracting(liveKeys).compactMap { identity in
        guard let pkg = snapshotByIdentity[identity],
              let mgr = snapshotManagerByIdentity[identity]
        else { return nil }
        return MissingPackage(manager: mgr, package: pkg)
    }

    // VersionChanged: same identity, different version (never in added or removed)
    let versionChanged: [VersionChange] = snapshotKeys.intersection(liveKeys).compactMap { identity in
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

    /// Stable identity for `ForEach` keying — mirrors the `(manager, qualifier, name)` match key.
    public var id: String { "\(manager.rawValue):\(package.qualifier ?? ""):\(package.name)" }
}

/// Returns the snapshot entries whose package is not present in the live inventory.
///
/// Matching is on `(manager, qualifier, name)` — not version. The recovery question
/// is "is this package present at all", not "is this exact version present".
///
/// An empty result is a normal outcome meaning nothing is missing.
public func snapshotDiff(snapshot: Snapshot, livePackages: [Package]) -> [MissingPackage] {
    struct Identity: Hashable {
        let manager: PackageManager
        let qualifier: String?
        let name: String
    }

    let liveSet = Set(livePackages.map {
        Identity(manager: $0.manager, qualifier: $0.qualifier, name: $0.name)
    })

    var missing: [MissingPackage] = []
    for (manager, packages) in snapshot.payload.managers {
        for pkg in packages {
            let identity = Identity(manager: manager, qualifier: pkg.qualifier, name: pkg.name)
            if !liveSet.contains(identity) {
                missing.append(MissingPackage(manager: manager, package: pkg))
            }
        }
    }
    return missing
}
