import InstalloryCore
import SwiftUI

/// A small colored shield that summarizes how safe a package is to remove.
/// The full reasoning is available via the tooltip / accessibility label.
struct RemovalSafetyBadge: View {
    let verdict: RemovalSafetyVerdict

    var body: some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .help(helpText)
            .accessibilityLabel("Removal safety: \(verdict.safety.rawValue)")
            .accessibilityHint(helpText)
    }

    private var symbol: String {
        switch verdict.safety {
        case .safe:       "checkmark.shield"
        case .caution:    "exclamationmark.shield"
        case .leaveAlone: "xmark.shield"
        }
    }

    private var tint: Color {
        switch verdict.safety {
        case .safe:       .green
        case .caution:    .orange
        case .leaveAlone: .red
        }
    }

    private var helpText: String {
        let label: String
        switch verdict.safety {
        case .safe:       label = "Safe to remove"
        case .caution:    label = "Remove with care"
        case .leaveAlone: label = "Leave alone"
        }
        guard !verdict.reasons.isEmpty else { return label }
        return "\(label): \(verdict.reasons.joined(separator: " · "))"
    }
}
