/// How Installory handles snapshot capture before a per-package removal.
///
/// Stored in UserDefaults under `backshelf.settings.snapshotBeforeRemoval`.
/// The "backshelf." prefix is retained intentionally from the prior product name
/// to avoid silently resetting existing users' preferences on update.
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
