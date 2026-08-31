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
    static let automationDefaultRuleKey = "WallPainter.automation.defaultRule"
    static let automationSpaceRulesKey = "WallPainter.automation.spaceRules"

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

    var automationDefaultRule: WallpaperRule {
        didSet {
            persist(automationDefaultRule, forKey: Self.automationDefaultRuleKey)
            postChange()
        }
    }

    private(set) var automationSpaceRules: [String: WallpaperRule] {
        didSet {
            persist(automationSpaceRules, forKey: Self.automationSpaceRulesKey)
            postChange()
        }
    }

    /// Compatibility accessors for the original global Light/Dark preferences.
    /// They now read and write the All Spaces appearance rule.
    var automationLightWallpaperID: String? {
        get { automationDefaultRule.lightWallpaperID }
        set { updateDefaultLightWallpaperID(newValue) }
    }

    var automationDarkWallpaperID: String? {
        get { automationDefaultRule.darkWallpaperID }
        set { updateDefaultDarkWallpaperID(newValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedWallpaperID = defaults.string(forKey: Self.selectedWallpaperKey)
        showStatusBarItem = defaults.object(forKey: Self.showStatusBarItemKey) as? Bool ?? true
        automationEnabled = defaults.bool(forKey: Self.automationEnabledKey)

        if let storedRule = Self.decode(WallpaperRule.self, from: defaults, key: Self.automationDefaultRuleKey) {
            automationDefaultRule = storedRule
        } else {
            let migratedRule = WallpaperRule.appearance(
                lightWallpaperID: defaults.string(forKey: Self.automationLightWallpaperKey),
                darkWallpaperID: defaults.string(forKey: Self.automationDarkWallpaperKey)
            )
            automationDefaultRule = migratedRule
            if let data = try? JSONEncoder().encode(migratedRule) {
                defaults.set(data, forKey: Self.automationDefaultRuleKey)
            }
        }

        automationSpaceRules = Self.decode(
            [String: WallpaperRule].self,
            from: defaults,
            key: Self.automationSpaceRulesKey
        ) ?? [:]
    }

    func spaceRule(for spaceID: String) -> WallpaperRule? {
        automationSpaceRules[spaceID]
    }

    func setSpaceRule(_ rule: WallpaperRule?, for spaceID: String) {
        guard !spaceID.isEmpty else { return }

        if let rule {
            automationSpaceRules[spaceID] = rule
        } else {
            automationSpaceRules.removeValue(forKey: spaceID)
        }
    }

    func resetSpaceRules() {
        guard !automationSpaceRules.isEmpty else { return }
        automationSpaceRules = [:]
    }

    private func updateDefaultLightWallpaperID(_ wallpaperID: String?) {
        var rule = automationDefaultRule
        rule.mode = .appearance
        rule.lightWallpaperID = wallpaperID
        automationDefaultRule = rule
    }

    private func updateDefaultDarkWallpaperID(_ wallpaperID: String?) {
        var rule = automationDefaultRule
        rule.mode = .appearance
        rule.darkWallpaperID = wallpaperID
        automationDefaultRule = rule
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
