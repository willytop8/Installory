import InstalloryCore
import SwiftUI

struct ManagerBadge: View {
    let manager: PackageManager

    var body: some View {
        Text(manager.badgeLabel)
            .font(.system(.caption2, design: .default, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(manager.badgeColor.opacity(0.15))
            .foregroundStyle(manager.badgeColor)
            .clipShape(Capsule())
            .accessibilityLabel(manager.displayName)
            .accessibilityAddTraits(.isStaticText)
            .help(manager.displayName)
    }
}

#Preview {
    HStack(spacing: 8) {
        ManagerBadge(manager: .brew)
        ManagerBadge(manager: .brewCask)
        ManagerBadge(manager: .pip)
        ManagerBadge(manager: .npm)
    }
    .padding()
}
