import XCTest

@testable import WallPainter

@MainActor
final class WallPainterPreferencesTests: XCTestCase {
    func testHideMenuBarIconUsesTheInverseOfTheStoredVisibilityPreference() {
        let suiteName = "WallPainterPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = WallPainterPreferences(defaults: defaults)

        XCTAssertFalse(preferences.hideMenuBarIcon)
        XCTAssertTrue(preferences.showStatusBarItem)

        preferences.hideMenuBarIcon = true

        XCTAssertTrue(preferences.hideMenuBarIcon)
        XCTAssertFalse(preferences.showStatusBarItem)

        preferences.hideMenuBarIcon = false

        XCTAssertFalse(preferences.hideMenuBarIcon)
        XCTAssertTrue(preferences.showStatusBarItem)
    }

    func testWallpaperProtectionDefaultsToEnabledAndPersists() {
        let suiteName = "WallPainterPreferencesProtectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = WallPainterPreferences(defaults: defaults)

        XCTAssertTrue(preferences.wallpaperProtectionEnabled)

        preferences.wallpaperProtectionEnabled = false

        let reloaded = WallPainterPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.wallpaperProtectionEnabled)
    }

    func testSpaceAPIDisconnectNotificationsDefaultToOffAndPersist() {
        let suiteName = "WallPainterPreferencesSpaceAPINotificationsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = WallPainterPreferences(defaults: defaults)

        XCTAssertFalse(preferences.notifyOnSpaceAPIDisconnect)

        preferences.notifyOnSpaceAPIDisconnect = true

        let reloaded = WallPainterPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.notifyOnSpaceAPIDisconnect)
    }

    func testDefaultRulePersistsAsManualOrConfiguredValue() throws {
        let suiteName = "WallPainterPreferencesDefaultRuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = WallPainterPreferences(defaults: defaults)
        XCTAssertEqual(preferences.defaultWallpaperRule, .manual)

        preferences.defaultWallpaperRule = .appearance(
            lightWallpaperID: "light-wallpaper",
            darkWallpaperID: "dark-wallpaper"
        )

        let reloaded = WallPainterPreferences(defaults: defaults)

        XCTAssertEqual(
            reloaded.defaultWallpaperRule,
            .appearance(lightWallpaperID: "light-wallpaper", darkWallpaperID: "dark-wallpaper")
        )
        XCTAssertNotNil(defaults.data(forKey: WallPainterPreferences.defaultWallpaperRuleKey))
    }

    func testSpaceRulesCanBeSavedAndReset() {
        let suiteName = "WallPainterPreferencesSpaceRulesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = WallPainterPreferences(defaults: defaults)
        let rule = WallpaperRule.fixed("wallpaper")

        preferences.setSpaceRule(rule, for: "space-1")
        XCTAssertEqual(preferences.spaceRule(for: "space-1"), rule)

        preferences.resetSpaceOverrides()
        XCTAssertNil(preferences.spaceRule(for: "space-1"))
    }
}
