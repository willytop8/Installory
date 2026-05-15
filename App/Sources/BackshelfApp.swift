import SwiftUI

@main
struct BackshelfApp: App {
    @State private var coordinator = AppCoordinator()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
        }
        .windowResizability(.contentSize)
    }
}
