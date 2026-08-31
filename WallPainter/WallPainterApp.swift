import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var wallpaperModel: WallpaperModel!
    private(set) var preferences: WallPainterPreferences!
    private(set) var statusBarController: StatusBarController?
    private(set) var automationCoordinator: WallpaperAutomationCoordinator?
    private(set) var spaceAPIClient: SpaceAPIClient?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let preferences = WallPainterPreferences()
        let wallpaperModel = WallpaperModel(preferences: preferences)
        let spaceAPIClient = SpaceAPIClient()
        self.preferences = preferences
        self.wallpaperModel = wallpaperModel
        self.spaceAPIClient = spaceAPIClient

        wallpaperModel.refresh()

        let automationCoordinator = WallpaperAutomationCoordinator(
            model: wallpaperModel,
            preferences: preferences,
            spaceProvider: spaceAPIClient
        )
        self.automationCoordinator = automationCoordinator

        statusBarController = StatusBarController(
            model: wallpaperModel,
            preferences: preferences,
            automationCoordinator: automationCoordinator,
            spaceProvider: spaceAPIClient
        )
        automationCoordinator.start()
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
