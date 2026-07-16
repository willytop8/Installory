/// How Installory handles snapshot capture before a per-package removal.
///
/// Stored under the canonical `app.installory.settings.snapshotBeforeRemoval`
/// UserDefaults key. A one-time migration imports the legacy Backshelf value.
/// Batch cleanup is always snapshotted regardless of this setting.
enum SnapshotPreference: String, CaseIterable {
    case always = "always"
    case never  = "never"
    case ask    = "ask"

    var displayName: String {
        switch self {
        case .always: "Always"
        case .never:  "Never"
        case .ask:    "Ask each time"
        }
    }
}
