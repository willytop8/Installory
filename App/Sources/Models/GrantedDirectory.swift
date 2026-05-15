import Foundation

struct GrantedDirectory: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let bookmark: Data

    var displayPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var managersUnlocked: String {
        let home = NSHomeDirectory()
        if path.hasPrefix("/opt/homebrew") || path.hasPrefix("/usr/local") {
            return "Homebrew, pip, npm"
        } else if path.hasPrefix("\(home)/.pyenv") {
            return "pip"
        } else if path.hasPrefix("\(home)/.nvm") || path.hasPrefix("\(home)/.volta") {
            return "npm"
        }
        return "All managers"
    }
}
