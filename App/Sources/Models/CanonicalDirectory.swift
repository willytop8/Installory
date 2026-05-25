import InstalloryCore
import Foundation

struct CanonicalDirectory: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let managers: [PackageManager]

    var displayPath: String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    var subtitle: String {
        managers.map(\.displayName).joined(separator: ", ")
    }

    // All canonical directories for this Mac architecture.
    static func all(isAppleSilicon: Bool) -> [CanonicalDirectory] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs: [CanonicalDirectory] = []
        if isAppleSilicon {
            dirs.append(.init(path: "/opt/homebrew", managers: [.brew, .brewCask, .pip, .npm, .gem]))
        } else {
            dirs.append(.init(path: "/usr/local", managers: [.brew, .brewCask, .pip, .npm, .gem]))
        }
        dirs.append(.init(path: "\(home)/.pyenv", managers: [.pip]))
        dirs.append(.init(path: "\(home)/.nvm", managers: [.npm]))
        dirs.append(.init(path: "\(home)/.volta", managers: [.npm]))
        dirs.append(.init(path: "\(home)/.local/share/pipx", managers: [.pipx]))
        dirs.append(.init(path: "\(home)/.cargo", managers: [.cargo]))
        dirs.append(.init(path: "\(home)/.rbenv", managers: [.gem]))
        dirs.append(.init(path: "\(home)/.gem", managers: [.gem]))
        dirs.append(.init(path: "/Applications", managers: [.mas]))
        dirs.append(.init(path: "\(home)/Applications", managers: [.mas]))
        return dirs
    }
}
