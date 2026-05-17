/// A plain-English description of a package.
///
/// Descriptions are served at runtime by `DescriptionStore`, which loads the
/// bundled JSON corpus (`descriptions.json`) and answers lookups by
/// `(manager, name)`. This struct is the domain model for a description entry;
/// the store uses a plain `[String: String]` dictionary internally for
/// efficiency and does not persist `Description` values to SQLite.
public struct Description: Codable, Sendable {
    public let manager: PackageManager
    public let name: String
    /// One to two plain-English sentences suitable for non-technical readers.
    public let text: String

    public init(manager: PackageManager, name: String, text: String) {
        self.manager = manager
        self.name = name
        self.text = text
    }
}
