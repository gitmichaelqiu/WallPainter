import Foundation
import Observation

@MainActor
@Observable
final class WallPainterPreferences {
    static let selectedWallpaperKey = "WallPainter.selectedWallpaperID"
    static let showStatusBarItemKey = "WallPainter.showStatusBarItem"
    static let defaultWallpaperRuleKey = "WallPainter.defaultWallpaperRule"
    static let spaceOverridesKey = "WallPainter.spaceOverrides"

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

    var defaultWallpaperRule: WallpaperRule {
        didSet {
            persist(defaultWallpaperRule, forKey: Self.defaultWallpaperRuleKey)
            postChange()
        }
    }

    private(set) var spaceOverrides: [String: WallpaperRule] {
        didSet {
            persist(spaceOverrides, forKey: Self.spaceOverridesKey)
            postChange()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedWallpaperID = defaults.string(forKey: Self.selectedWallpaperKey)
        showStatusBarItem = defaults.object(forKey: Self.showStatusBarItemKey) as? Bool ?? true
        defaultWallpaperRule = Self.decode(
            WallpaperRule.self,
            from: defaults,
            key: Self.defaultWallpaperRuleKey
        ) ?? .manual

        spaceOverrides = Self.decode(
            [String: WallpaperRule].self,
            from: defaults,
            key: Self.spaceOverridesKey
        ) ?? [:]
    }

    func spaceRule(for spaceID: String) -> WallpaperRule? {
        spaceOverrides[spaceID]
    }

    func setSpaceRule(_ rule: WallpaperRule?, for spaceID: String) {
        guard !spaceID.isEmpty else { return }

        if let rule {
            spaceOverrides[spaceID] = rule
        } else {
            spaceOverrides.removeValue(forKey: spaceID)
        }
    }

    func resetSpaceOverrides() {
        guard !spaceOverrides.isEmpty else { return }
        spaceOverrides = [:]
    }

    private func persist(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from defaults: UserDefaults,
        key: String
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
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
