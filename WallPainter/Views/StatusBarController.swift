import AppKit

struct WallpaperMenuEntry: Equatable {
    let id: String
    let title: String
    let isCurrent: Bool
}

enum WallpaperMenuEntries {
    static func make(
        wallpapers: [WallpaperItem],
        currentWallpaperID: String?
    ) -> [WallpaperMenuEntry] {
        wallpapers.map { wallpaper in
            WallpaperMenuEntry(
                id: wallpaper.id,
                title: wallpaper.name,
                isCurrent: wallpaper.id == currentWallpaperID
            )
        }
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private let model: WallpaperModel
    private let preferences: WallPainterPreferences
    private let statusItem: NSStatusItem
    private var settingsWindowController: NSWindowController?

    init(model: WallpaperModel, preferences: WallPainterPreferences) {
        self.model = model
        self.preferences = preferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(wallpaperModelDidChange),
            name: .wallPainterWallpaperModelDidChange,
            object: model
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: .wallPainterPreferencesDidChange,
            object: preferences
        )
        rebuildMenu()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureStatusItem() {
        statusItem.isVisible = preferences.showStatusBarItem
        guard let button = statusItem.button else { return }

        let image = NSImage(
            systemSymbolName: "photo.tv",
            accessibilityDescription: "WallPainter"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "WallPainter"
        button.setAccessibilityLabel("WallPainter")
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let switchItem = NSMenuItem(title: "Switch", action: nil, keyEquivalent: "")
        let switchMenu = NSMenu(title: "Switch")
        switchMenu.autoenablesItems = false

        let entries = WallpaperMenuEntries.make(
            wallpapers: model.items,
            currentWallpaperID: model.currentWallpaperID
        )

        if entries.isEmpty {
            let emptyItem = NSMenuItem(
                title: "No installed wallpapers",
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            switchMenu.addItem(emptyItem)
        } else {
            for entry in entries {
                let item = NSMenuItem(
                    title: entry.title,
                    action: #selector(switchWallpaper(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.id
                item.state = entry.isCurrent ? .on : .off
                switchMenu.addItem(item)
            }
        }

        switchItem.submenu = switchMenu
        menu.addItem(switchItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit WallPainter",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func openSettingsWindow(tab: SettingsTab? = nil) {
        NSApp.setActivationPolicy(.regular)

        if let settingsWindowController {
            settingsWindowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.minSize = NSSize(width: 750, height: 550)
        window.collectionBehavior = [.participatesInCycle]
        window.level = .normal

        let settingsViewController = SettingsHostingController(
            model: model,
            preferences: preferences,
            initialTab: tab
        )
        window.contentViewController = settingsViewController
        window.delegate = self

        let windowController = NSWindowController(window: window)
        settingsWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func wallpaperModelDidChange() {
        rebuildMenu()
    }

    @objc private func preferencesDidChange() {
        statusItem.isVisible = preferences.showStatusBarItem
        rebuildMenu()
    }

    @objc private func switchWallpaper(_ sender: NSMenuItem) {
        guard let wallpaperID = sender.representedObject as? String else { return }
        model.applyWallpaper(id: wallpaperID)
        rebuildMenu()
    }

    @objc func openSettingsWindow() {
        openSettingsWindow(tab: .general)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.synchronizeCurrentWallpaper()
        rebuildMenu()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindowController?.window else { return }

        settingsWindowController = nil
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
