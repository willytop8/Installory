import Foundation

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
