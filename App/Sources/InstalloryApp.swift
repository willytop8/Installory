import InstalloryCore
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

                Divider()

                Button(coordinator.isDemoMode ? "Exit Demo Mode" : "Load Sample Data") {
                    if coordinator.isDemoMode {
                        coordinator.exitDemoMode()
                    } else {
                        coordinator.enterDemoMode()
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Export Inventory as CSV\u{2026}") {
                    coordinator.exportInventory(format: .csv)
                }
                .disabled(coordinator.packages.isEmpty)
                .keyboardShortcut("e", modifiers: .command)

                Button("Export Inventory as Markdown\u{2026}") {
                    coordinator.exportInventory(format: .markdown)
                }
                .disabled(coordinator.packages.isEmpty)
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Show Data Folder in Finder") {
                    coordinator.revealDataFolder()
                }
            }
        }

        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}
