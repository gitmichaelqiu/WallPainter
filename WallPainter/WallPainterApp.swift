import SwiftUI

@main
struct WallPainterApp: App {
    var body: some Scene {
        WindowGroup("WallPainter") {
            SettingsView()
        }
        .defaultSize(width: 750, height: 550)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)

        Settings {
            SettingsView()
        }
        .defaultSize(width: 750, height: 550)
        .windowResizability(.contentSize)
    }
}
