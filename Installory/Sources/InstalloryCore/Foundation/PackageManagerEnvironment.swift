import Foundation

/// Environment values that can relocate package-manager installation roots.
///
/// Production scanners default to ``current``. Tests and other hosts can inject
/// an explicit dictionary, keeping path discovery deterministic and avoiding
/// scattered reads from `ProcessInfo`.
public struct PackageManagerEnvironment: Sendable {
    /// A snapshot of the current process environment.
    public static let current = PackageManagerEnvironment(
        values: ProcessInfo.processInfo.environment
    )

    /// An environment with no package-manager overrides.
    public static let empty = PackageManagerEnvironment(values: [:])

    private let values: [String: String]

    public init(values: [String: String]) {
        self.values = [
            "CARGO_HOME": values["CARGO_HOME"],
            "GEM_HOME": values["GEM_HOME"],
            "PYENV_ROOT": values["PYENV_ROOT"],
            "NVM_DIR": values["NVM_DIR"],
            "PIPX_HOME": values["PIPX_HOME"],
        ].compactMapValues { $0 }
    }

    func cargoHome(fallback: URL) -> URL {
        absoluteDirectory(named: "CARGO_HOME") ?? fallback
    }

    func gemHome(fallback: URL) -> URL {
        absoluteDirectory(named: "GEM_HOME") ?? fallback
    }

    func pyenvRoot(fallback: URL) -> URL {
        absoluteDirectory(named: "PYENV_ROOT") ?? fallback
    }

    func nvmDirectory(fallback: URL) -> URL {
        absoluteDirectory(named: "NVM_DIR") ?? fallback
    }

    func pipxHome(fallback: URL) -> URL {
        absoluteDirectory(named: "PIPX_HOME") ?? fallback
    }

    /// Package-manager roots are expected to be absolute when inherited by a
    /// GUI app. Relative values depend on a shell working directory that the app
    /// does not share, so treating them as invalid is safer than scanning an
    /// unrelated path inside the app container.
    private func absoluteDirectory(named name: String) -> URL? {
        guard let value = values[name], !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              NSString(string: value).isAbsolutePath
        else { return nil }

        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }
}
