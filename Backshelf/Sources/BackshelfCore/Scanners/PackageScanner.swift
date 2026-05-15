import Foundation

/// The uniform interface all package manager scanners must implement.
///
/// Scanners are concrete `struct`s or `final class`es. No subclassing —
/// composition only. Each scanner reads on-disk state directly; no subprocess
/// invocations are ever made.
public protocol PackageScanner: Sendable {
    /// The package manager this scanner handles.
    var manager: PackageManager { get }

    /// Returns `true` if the manager appears to be installed on this Mac.
    ///
    /// Cheap: checks for the binary or known directories; does not enumerate
    /// packages. Call before `scan()` to skip unavailable managers.
    func isAvailable() async -> Bool

    /// Enumerate all installed packages for this manager.
    ///
    /// Throws `ScannerError` on unrecoverable failure. Returns an empty array
    /// if the manager is available but has no installed packages.
    func scan() async throws -> [Package]
}

/// Errors that a `PackageScanner` may throw on unrecoverable failure.
public enum ScannerError: Error, Sendable {
    case binaryNotFound(String)
    case timeout
    case malformedOutput(String)
    case unsupportedVersion(detected: String, minimum: String)
}
