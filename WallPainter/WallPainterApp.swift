import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var wallpaperModel: WallpaperModel!
    private(set) var preferences: WallPainterPreferences!
    private(set) var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let preferences = WallPainterPreferences()
        let wallpaperModel = WallpaperModel(preferences: preferences)
        self.preferences = preferences
        self.wallpaperModel = wallpaperModel

        wallpaperModel.refresh()
        statusBarController = StatusBarController(
            model: wallpaperModel,
            preferences: preferences
        )
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        statusBarController?.openSettingsWindow()
        return true
    }
}

@main
struct WallPainterApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
