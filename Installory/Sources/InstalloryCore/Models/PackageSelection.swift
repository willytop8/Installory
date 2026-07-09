/// Re-resolves a held package selection against a freshly scanned inventory.
///
/// `Package` is a value type, so a selection captured before a scan keeps whatever
/// version, flags, and dependency list it had at capture time. After the inventory
/// is replaced the detail pane would otherwise keep rendering that stale struct
/// until the user clicked a different row.
public enum PackageSelection {

    /// Returns the package in `packages` sharing `selection`'s stable id.
    ///
    /// Returns `nil` when nothing was selected, or when the selected package is no
    /// longer in the inventory — it was uninstalled, or its scanner failed this run.
    public static func resolve(_ selection: Package?, in packages: [Package]) -> Package? {
        guard let selection else { return nil }
        return packages.first { $0.id == selection.id }
    }
}
