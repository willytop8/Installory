import BackshelfCore
import SwiftUI

extension PackageManager {
    var displayName: String {
        switch self {
        case .brew: "Homebrew"
        case .brewCask: "Homebrew Cask"
        case .pip: "pip"
        case .pipx: "pipx"
        case .npm: "npm"
        case .cargo: "Cargo"
        case .gem: "RubyGems"
        case .mas: "Mac App Store"
        }
    }

    var badgeLabel: String {
        switch self {
        case .brew: "brew"
        case .brewCask: "cask"
        case .pip: "pip"
        case .pipx: "pipx"
        case .npm: "npm"
        case .cargo: "cargo"
        case .gem: "gem"
        case .mas: "mas"
        }
    }

    // Accessible, distinct badge colors. brew/brewCask share amber (both are Homebrew).
    var badgeColor: Color {
        switch self {
        case .brew, .brewCask: Color(red: 0.85, green: 0.55, blue: 0.05)
        case .pip, .pipx: Color(red: 0.20, green: 0.45, blue: 0.90)
        case .npm: Color(red: 0.85, green: 0.15, blue: 0.15)
        case .cargo: Color(red: 0.60, green: 0.30, blue: 0.10)
        case .gem: Color(red: 0.75, green: 0.10, blue: 0.50)
        case .mas: Color(red: 0.45, green: 0.20, blue: 0.85)
        }
    }

    var sidebarSymbol: String {
        switch self {
        case .brew, .brewCask: "shippingbox"
        case .pip, .pipx: "terminal"
        case .npm: "globe"
        case .cargo: "shippingbox.fill"
        case .gem: "sparkles"
        case .mas: "app.badge"
        }
    }
}
