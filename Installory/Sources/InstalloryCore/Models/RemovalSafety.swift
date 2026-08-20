import Foundation

/// How safe it is to remove a package, distilled from Installory's dependency,
/// denylist, and script-eligibility analyses.
///
/// This is a coarse, honest signal for people who are nervous about deleting
/// things. It never claims to know how the package is used outside Installory's
/// inventory — it only reports what Installory can actually see.
public enum RemovalSafety: String, Sendable, Equatable, Hashable {
    /// Nothing in the inventory depends on it, and Installory can generate a
    /// clean removal command. Generally fine to remove.
    case safe

    /// Removable, but with caveats: something depends on it, it was installed
    /// implicitly, or its removal path needs manual care.
    case caution

    /// Should not be removed through Installory — read-only, essential, or
    /// removable only through another channel (e.g. the App Store).
    case leaveAlone
}

/// A removal-safety verdict together with the plain-English reasons behind it.
public struct RemovalSafetyVerdict: Sendable, Equatable {
    public let safety: RemovalSafety
    public let reasons: [String]

    public init(safety: RemovalSafety, reasons: [String]) {
        self.safety = safety
        self.reasons = reasons
    }
}
