import Foundation
import InstalloryCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
                pageContent
                VStack(spacing: 14) {
                    navigationRow
                    Button {
                        coordinator.enterDemoMode()
                        dismiss()
                    } label: {
                        Label("Explore with Sample Data", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.link)
                    .help("Load a pre-populated sample inventory so you can explore every feature without granting access to any folders.")
                }
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
                message: "Installory scans your Mac for packages installed by Homebrew, pip, pipx, npm, Cargo, RubyGems, and the Mac App Store — giving you a clear picture of what's installed."
            )
        case 1:
            OnboardingPanel(
                systemImage: "shield.lefthalf.filled",
                title: "We never delete anything",
                message: "When you want to clean up, Installory generates a shell script you review and run yourself in Terminal. Nothing is removed without your explicit action."
            )
        case 2:
            BadgeLegendPanel()
        default:
            OnboardingPanel(
                systemImage: "folder.badge.plus",
                title: "Grant access to get started",
                message: "Installory reads — but never writes — your package directories. Grant access to /opt/homebrew (or /usr/local on Intel) to start with Homebrew, pip, npm, and RubyGems packages."
            )
        }
    }

    private var navigationRow: some View {
        HStack {
            // Page dots
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            if page < 3 {
                Button("Next") {
                    withAnimation { page += 1 }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                HStack(spacing: 12) {
                    // Only offer the one-click Homebrew grant when that folder
                    // actually exists. On a Mac without Homebrew, pointing the
                    // open panel at a missing/system path can lead the user to
                    // grant a protected directory and trigger a macOS
                    // authentication sheet — so we fall back to a plain folder
                    // picker that starts in the user's home folder.
                    if brewRootExists {
                        Button("Grant Access to \(brewRoot)") {
                            Task {
                                await coordinator.grantDirectory(suggestedPath: brewRoot)
                                complete()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Choose a Folder to Scan…") {
                            Task {
                                await coordinator.grantCustomDirectory()
                                complete()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

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

    /// Whether the Homebrew prefix exists as a directory on this Mac. When it
    /// doesn't (e.g. Homebrew isn't installed), onboarding avoids pointing the
    /// folder picker at it.
    private var brewRootExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: brewRoot, isDirectory: &isDir) && isDir.boolValue
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

/// Onboarding page that introduces the colored manager badges so users can
/// recognize them at a glance in the package list and detail views.
private struct BadgeLegendPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text("What the badges mean")
                .font(.title2)
                .fontWeight(.bold)
            Text("Each badge marks which package manager installed an item.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(PackageManager.allCases, id: \.self) { manager in
                    HStack(spacing: 6) {
                        ManagerBadge(manager: manager)
                        Text(manager.displayName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: 360)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppCoordinator())
}
