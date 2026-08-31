import AppKit

enum WallpaperMenuCheckState: Equatable {
    case on
    case mixed
    case off
    case disabled
}

struct WallpaperMenuEntry: Equatable {
    let id: String
    let title: String
    let state: WallpaperMenuCheckState

    init(id: String, title: String, isCurrent: Bool) {
        self.id = id
        self.title = title
        state = isCurrent ? .on : .off
    }

    init(id: String, title: String, state: WallpaperMenuCheckState) {
        self.id = id
        self.title = title
        self.state = state
    }

    var isCurrent: Bool {
        state == .on
    }
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

    static func make(
        wallpapers: [WallpaperItem],
        currentWallpaperIDsBySpaceID: [String: String],
        activeSpaceTargets: [WallpaperSpaceTarget],
        isSpaceAPIAvailable: Bool
    ) -> [WallpaperMenuEntry] {
        let targets = uniqueTargets(activeSpaceTargets)
        let isUnavailable = !isSpaceAPIAvailable || targets.isEmpty
        let activeWallpaperIDs = targets.compactMap {
            currentWallpaperIDsBySpaceID[$0.spaceID]
        }
        let hasUnknownWallpaper = activeWallpaperIDs.count < targets.count

        return wallpapers.map { wallpaper in
            let state: WallpaperMenuCheckState
            if isUnavailable {
                state = .disabled
            } else if !hasUnknownWallpaper,
                      activeWallpaperIDs.allSatisfy({ $0 == wallpaper.id }) {
                state = .on
            } else if hasUnknownWallpaper || activeWallpaperIDs.contains(wallpaper.id) {
                state = .mixed
            } else {
                state = .off
            }

            return WallpaperMenuEntry(
                id: wallpaper.id,
                title: wallpaper.name,
                state: state
            )
        }
    }

    private static func uniqueTargets(
        _ targets: [WallpaperSpaceTarget]
    ) -> [WallpaperSpaceTarget] {
        var seenIDs = Set<String>()
        return targets.filter { target in
            !target.spaceID.isEmpty && seenIDs.insert(target.spaceID).inserted
        }
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private let model: WallpaperModel
    private let preferences: WallPainterPreferences
    private let automationCoordinator: WallpaperAutomationCoordinator
    private let spaceProvider: (any SpaceAPIProviding)?
    private let statusItem: NSStatusItem
    private var settingsWindowController: NSWindowController?

    init(
        model: WallpaperModel,
        preferences: WallPainterPreferences,
        automationCoordinator: WallpaperAutomationCoordinator,
        spaceProvider: (any SpaceAPIProviding)? = nil
    ) {
        self.model = model
        self.preferences = preferences
        self.automationCoordinator = automationCoordinator
        self.spaceProvider = spaceProvider
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spaceStateDidChange(_:)),
            name: .wallPainterSpaceSnapshotDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spaceStateDidChange(_:)),
            name: .wallPainterSpaceAvailabilityDidChange,
            object: nil
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

        let entries: [WallpaperMenuEntry]
        if spaceProvider == nil {
            entries = WallpaperMenuEntries.make(
                wallpapers: model.items,
                currentWallpaperID: model.currentWallpaperID
            )
        } else {
            entries = WallpaperMenuEntries.make(
                wallpapers: model.items,
                currentWallpaperIDsBySpaceID: model.currentWallpaperIDsBySpaceID,
                activeSpaceTargets: currentSpaceTargets,
                isSpaceAPIAvailable: spaceProvider?.isAvailable == true
            )
        }

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
                item.state = menuState(for: entry.state)
                item.isEnabled = entry.state != .disabled
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.center()
        window.collectionBehavior = [.participatesInCycle, .fullScreenNone]
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.level = .normal

        let settingsViewController = SettingsHostingController(
            model: model,
            preferences: preferences,
            automationCoordinator: automationCoordinator,
            spaceProvider: spaceProvider,
            initialTab: tab
        )
        window.contentViewController = settingsViewController
        window.minSize = NSSize(width: 750, height: 550)
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

    @objc private func spaceStateDidChange(_ notification: Notification) {
        guard let spaceProvider,
              notification.object as AnyObject? === spaceProvider as AnyObject?
        else { return }

        synchronizeActiveSpaceState()
        rebuildMenu()
    }

    @objc private func switchWallpaper(_ sender: NSMenuItem) {
        guard let wallpaperID = sender.representedObject as? String else { return }

        if spaceProvider == nil {
            _ = model.applyWallpaper(id: wallpaperID)
        } else {
            guard spaceProvider?.isAvailable == true,
                  !currentSpaceTargets.isEmpty
            else { return }

            synchronizeActiveSpaceState()
            _ = model.applyWallpaper(id: wallpaperID, to: currentSpaceTargets)
        }
        rebuildMenu()
    }

    @objc func openSettingsWindow() {
        openSettingsWindow(tab: .general)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        synchronizeActiveSpaceState()
        rebuildMenu()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindowController?.window else { return }

        settingsWindowController = nil
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var currentSpaceTargets: [WallpaperSpaceTarget] {
        guard let snapshot = spaceProvider?.snapshot else { return [] }
        let spacesByID = Dictionary(uniqueKeysWithValues: snapshot.spaces
            .filter { !$0.isFullscreen }
            .map { ($0.id, $0) })
        return snapshot.currentSpaceIDs.compactMap { spaceID in
            guard let space = spacesByID[spaceID] else { return nil }
            return WallpaperSpaceTarget(spaceID: space.id, displayID: space.displayID)
        }
    }

    private func synchronizeActiveSpaceState() {
        guard spaceProvider != nil else {
            model.synchronizeCurrentWallpaper()
            return
        }

        guard spaceProvider?.isAvailable == true else {
            model.setActiveSpaceTargets([])
            return
        }

        model.synchronizeCurrentWallpapers(for: currentSpaceTargets)
    }

    private func menuState(for state: WallpaperMenuCheckState) -> NSControl.StateValue {
        switch state {
        case .on:
            return .on
        case .mixed:
            return .mixed
        case .off, .disabled:
            return .off
        }
    }
}
