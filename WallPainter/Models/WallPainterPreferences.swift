import Foundation
import Observation

@MainActor
@Observable
final class WallPainterPreferences {
    static let selectedWallpaperKey = "WallPainter.selectedWallpaperID"
    static let showStatusBarItemKey = "WallPainter.showStatusBarItem"
    static let automationEnabledKey = "WallPainter.automation.enabled"
    static let automationLightWallpaperKey = "WallPainter.automation.lightWallpaperID"
    static let automationDarkWallpaperKey = "WallPainter.automation.darkWallpaperID"

    @ObservationIgnored private let defaults: UserDefaults

    var selectedWallpaperID: String? {
        didSet {
            persist(selectedWallpaperID, forKey: Self.selectedWallpaperKey)
            postChange()
        }
    }

    var showStatusBarItem: Bool {
        didSet {
            defaults.set(showStatusBarItem, forKey: Self.showStatusBarItemKey)
            postChange()
        }
    }

    var hideMenuBarIcon: Bool {
        get { !showStatusBarItem }
        set { showStatusBarItem = !newValue }
    }

    var automationEnabled: Bool {
        didSet {
            defaults.set(automationEnabled, forKey: Self.automationEnabledKey)
            postChange()
        }
    }

    var automationLightWallpaperID: String? {
        didSet {
            persist(automationLightWallpaperID, forKey: Self.automationLightWallpaperKey)
            postChange()
        }
    }

    var automationDarkWallpaperID: String? {
        didSet {
            persist(automationDarkWallpaperID, forKey: Self.automationDarkWallpaperKey)
            postChange()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedWallpaperID = defaults.string(forKey: Self.selectedWallpaperKey)
        showStatusBarItem = defaults.object(forKey: Self.showStatusBarItemKey) as? Bool ?? true
        automationEnabled = defaults.bool(forKey: Self.automationEnabledKey)
        automationLightWallpaperID = defaults.string(forKey: Self.automationLightWallpaperKey)
        automationDarkWallpaperID = defaults.string(forKey: Self.automationDarkWallpaperKey)
    }

    private func persist(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func postChange() {
        NotificationCenter.default.post(
            name: .wallPainterPreferencesDidChange,
            object: self
        )
    }
}

extension Notification.Name {
    static let wallPainterPreferencesDidChange = Notification.Name(
        "WallPainter.preferencesDidChange"
    )
}
