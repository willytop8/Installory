/// The package managers Backshelf can inventory.
public enum PackageManager: String, Codable, CaseIterable, Sendable {
    case brew
    case brewCask
    case pip
    case pipx
    case npm
    case cargo
    case gem
    case mas
}
