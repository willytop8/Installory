import SwiftUI

@main
struct InstalloryApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
        }

        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}
