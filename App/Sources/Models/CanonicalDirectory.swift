import InstalloryCore
import Foundation

struct CanonicalDirectory: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let managers: [PackageManager]

    var displayPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var subtitle: String {
        managers.map(\.displayName).joined(separator: ", ")
    }

    // All canonical directories for this Mac architecture.
    static func all(isAppleSilicon: Bool) -> [CanonicalDirectory] {
        let home = NSHomeDirectory()
        var dirs: [CanonicalDirectory] = []
        if isAppleSilicon {
            dirs.append(.init(path: "/opt/homebrew", managers: [.brew, .brewCask, .pip, .npm]))
        } else {
            dirs.append(.init(path: "/usr/local", managers: [.brew, .brewCask, .pip, .npm]))
        }
        dirs.append(.init(path: "\(home)/.pyenv", managers: [.pip]))
        dirs.append(.init(path: "\(home)/.nvm", managers: [.npm]))
        dirs.append(.init(path: "\(home)/.volta", managers: [.npm]))
        return dirs
    }
}
