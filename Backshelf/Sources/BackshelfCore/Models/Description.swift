/// A plain-English description of a package, loaded read-only from the
/// bundled descriptions corpus (`descriptions.db`).
///
/// The bundled SQLite file is separate from the app's writable database.
/// There is no writable description table — if a `(manager, name)` pair
/// is absent from the corpus, the UI shows "No description available".
///
/// GRDB conformances are deferred to the `DescriptionStore` implementation
/// in Phase 1, when the bundled DB path and read-only pool are wired up.
public struct Description: Codable, Sendable {
    public let manager: PackageManager
    public let name: String
    /// One to two plain-English sentences suitable for non-technical readers.
    public let text: String
}
