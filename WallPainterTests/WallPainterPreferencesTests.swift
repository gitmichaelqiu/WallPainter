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

    func testExistingAppearancePreferencesMigrateToAllSpacesRule() throws {
        let suiteName = "WallPainterPreferencesMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("light-wallpaper", forKey: WallPainterPreferences.automationLightWallpaperKey)
        defaults.set("dark-wallpaper", forKey: WallPainterPreferences.automationDarkWallpaperKey)

        let preferences = WallPainterPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.automationDefaultRule,
            .appearance(lightWallpaperID: "light-wallpaper", darkWallpaperID: "dark-wallpaper")
        )
        XCTAssertNotNil(defaults.data(forKey: WallPainterPreferences.automationDefaultRuleKey))
    }

    func testSpaceRulesCanBeSavedAndReset() {
        let suiteName = "WallPainterPreferencesSpaceRulesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = WallPainterPreferences(defaults: defaults)
        let rule = WallpaperRule.fixed("wallpaper")

        preferences.setSpaceRule(rule, for: "space-1")
        XCTAssertEqual(preferences.spaceRule(for: "space-1"), rule)

        preferences.resetSpaceRules()
        XCTAssertNil(preferences.spaceRule(for: "space-1"))
    }
}
