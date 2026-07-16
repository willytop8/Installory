import Foundation

extension PackageManager {
    /// Whether this manager's scanner emits one package row per installation, recording
    /// which one in `Package.qualifier`. Generated scripts must group these managers by
    /// qualifier and target each installation explicitly — see ``ManagerBinaryResolver``.
    var groupsByQualifier: Bool {
        switch self {
        case .pip, .npm, .gem: return true
        case .brew, .brewCask, .pipx, .uv, .cargo, .mas: return false
        }
    }
}

/// Resolves which manager client a generated command should invoke, given the
/// qualifier a scanner recorded on a package.
///
/// `NpmScanner` and `GemScanner` deliberately emit one row per qualifier — one
/// per nvm/Volta Node version, one per rbenv Ruby version. A bare `npm uninstall -g foo`
/// runs against whichever `npm` happens to be first on `PATH`, so selecting the same
/// package from two Node installs produces two identical commands that both target the
/// same install: one copy survives while the user believes both were removed.
///
/// This type is pure and filesystem-free: it derives paths from the qualifier's shape
/// alone. It never checks whether the resolved binary exists — the generated script is
/// reviewed and run by the user, and a wrong-but-visible absolute path is far safer
/// than a silently wrong-target removal.
public enum ManagerBinaryResolver {

    /// Every global `node_modules` root `NpmScanner` discovers — Homebrew prefixes,
    /// nvm versions, Volta images — has the shape `<prefix>/lib/node_modules`, so the
    /// colocated client is `<prefix>/bin/npm`.
    ///
    /// Returns the ambient `"npm"` when there is no qualifier, or when the qualifier
    /// does not have that shape.
    public static func npm(forQualifier qualifier: String?) -> String {
        guard let prefix = nodePrefix(forQualifier: qualifier) else { return "npm" }
        return prefix.appendingPathComponent("bin/npm").path
    }

    /// How a `gem` command should be scoped to a particular Ruby installation.
    ///
    /// Gem specification directories under a Ruby prefix look like
    /// `<prefix>/lib/ruby/gems/<api-version>/specifications`, so the colocated client is
    /// `<prefix>/bin/gem` — that covers Homebrew rubies and rbenv versions. Roots that
    /// don't follow that shape (`/Library/Ruby/Gems/…`, `~/.gem/ruby/…`) have no
    /// colocated client, so the ambient `gem` is scoped with `--install-dir` instead.
    /// Either way the command names exactly one gem installation.
    public struct GemCommand: Sendable, Equatable {
        /// `"gem"`, or an absolute path to the client colocated with the qualifier.
        public let binary: String
        /// The gem root to pass to `--install-dir`, when `binary` is the ambient `gem`.
        public let installDir: String?

        public static let ambient = GemCommand(binary: "gem", installDir: nil)
    }

    public static func gem(forQualifier qualifier: String?) -> GemCommand {
        guard let specifications = normalized(qualifier),
              specifications.lastPathComponent == "specifications"
        else { return .ambient }

        let gemRoot = specifications.deletingLastPathComponent()

        if let prefix = rubyPrefix(forGemRoot: gemRoot) {
            return GemCommand(binary: prefix.appendingPathComponent("bin/gem").path, installDir: nil)
        }
        return GemCommand(binary: "gem", installDir: gemRoot.path)
    }

    // MARK: - Private

    private static func normalized(_ qualifier: String?) -> URL? {
        guard let qualifier, !qualifier.isEmpty else { return nil }
        return URL(fileURLWithPath: qualifier).standardizedFileURL
    }

    /// `<prefix>/lib/node_modules` → `<prefix>`
    private static func nodePrefix(forQualifier qualifier: String?) -> URL? {
        guard let nodeModules = normalized(qualifier),
              nodeModules.lastPathComponent == "node_modules"
        else { return nil }

        let lib = nodeModules.deletingLastPathComponent()
        guard lib.lastPathComponent == "lib" else { return nil }

        let prefix = lib.deletingLastPathComponent()
        return prefix.path == "/" ? nil : prefix
    }

    /// `<prefix>/lib/ruby/gems/<api-version>` (or `<prefix>/lib/ruby/gems`) → `<prefix>`
    private static func rubyPrefix(forGemRoot gemRoot: URL) -> URL? {
        var candidate = gemRoot
        // Homebrew and rbenv both nest an API-version directory under `gems`;
        // `GemScanner` also accepts a `specifications` dir directly under `gems`.
        if candidate.lastPathComponent != "gems" {
            candidate = candidate.deletingLastPathComponent()
        }
        guard candidate.lastPathComponent == "gems" else { return nil }

        let ruby = candidate.deletingLastPathComponent()
        guard ruby.lastPathComponent == "ruby" else { return nil }

        let lib = ruby.deletingLastPathComponent()
        guard lib.lastPathComponent == "lib" else { return nil }

        let prefix = lib.deletingLastPathComponent()
        return prefix.path == "/" ? nil : prefix
    }
}
