/// How Installory handles snapshot capture before a per-package removal.
///
/// Stored in UserDefaults under `installory.settings.snapshotBeforeRemoval`.
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
