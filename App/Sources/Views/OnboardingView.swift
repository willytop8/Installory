import InstalloryCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 32) {
                pageContent
                navigationRow
            }
            .padding(40)

            Button("Skip") {
                complete()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(20)
        }
        .frame(width: 480, height: 360)
    }

    // MARK: - Pages

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0:
            OnboardingPanel(
                systemImage: "shippingbox.fill",
                title: "Meet Installory",
                message: "Installory scans your Mac for packages installed by Homebrew, pip, npm, and other tools — giving you a clear picture of what's installed and why."
            )
        case 1:
            OnboardingPanel(
                systemImage: "shield.lefthalf.filled",
                title: "We never delete anything",
                message: "When you want to clean up, Installory generates a shell script you review and run yourself in Terminal. Nothing is removed without your explicit action."
            )
        default:
            OnboardingPanel(
                systemImage: "folder.badge.plus",
                title: "Grant access to get started",
                message: "Installory reads — but never writes — your package directories. Grant access to /opt/homebrew (or /usr/local on Intel) to scan your Homebrew packages."
            )
        }
    }

    private var navigationRow: some View {
        HStack {
            // Page dots
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            if page < 2 {
                Button("Next") {
                    withAnimation { page += 1 }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                HStack(spacing: 12) {
                    Button("Grant Access to /opt/homebrew") {
                        Task {
                            await coordinator.grantDirectory(suggestedPath: brewRoot)
                            complete()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Skip for Now") {
                        complete()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Helpers

    private var brewRoot: String {
        #if arch(arm64)
        "/opt/homebrew"
        #else
        "/usr/local"
        #endif
    }

    private func complete() {
        coordinator.completeOnboarding()
        dismiss()
    }
}

private struct OnboardingPanel: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppCoordinator())
}
