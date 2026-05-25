import SwiftUI

@main
struct InstalloryApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
        }
        .commands {
            CommandMenu("Inventory") {
                Button("Refresh") {
                    Task { await coordinator.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(coordinator.isScanning)

                Button("Snapshot Now") {
                    Task { await coordinator.captureManualSnapshot() }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(coordinator.packages.isEmpty || coordinator.isScanning)

                Divider()

                Button("Grant Custom Directory\u{2026}") {
                    Task { await coordinator.grantCustomDirectory() }
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(coordinator.isCleanupMode ? "Exit Cleanup Mode" : "Enter Cleanup Mode") {
                    coordinator.isCleanupMode.toggle()
                    if !coordinator.isCleanupMode {
                        coordinator.selectedForCleanup = []
                    }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(coordinator.packages.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}
