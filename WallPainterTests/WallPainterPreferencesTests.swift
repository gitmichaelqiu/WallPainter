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

    func testLegacySpaceOverridesMigrateToStableIDsAndPersist() {
        let suiteName = "WallPainterPreferencesSpaceRuleMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = WallPainterPreferences(defaults: defaults)
        let rule = WallpaperRule.fixed("wallpaper")
        preferences.setSpaceRule(rule, for: "42001")

        let spaces = [
            SpaceDescriptor(
                id: "stable-space-id",
                name: "Research",
                displayID: "display-1",
                displayName: "Built-in Display",
                number: 1,
                isFullscreen: false,
                managedSpaceID: "42001"
            )
        ]

        XCTAssertEqual(preferences.migrateLegacySpaceOverrides(using: spaces), 1)
        XCTAssertNil(preferences.spaceRule(for: "42001"))
        XCTAssertEqual(preferences.spaceRule(for: "stable-space-id"), rule)
        XCTAssertEqual(
            WallPainterPreferences(defaults: defaults).spaceRule(for: "stable-space-id"),
            rule
        )
    }

    func testLegacySpaceOverridesRemainWhenMappingIsAmbiguousOrConflicts() {
        let suiteName = "WallPainterPreferencesSpaceRuleMigrationSafetyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = WallPainterPreferences(defaults: defaults)
        let legacyRule = WallpaperRule.fixed("legacy-wallpaper")
        let stableRule = WallpaperRule.fixed("stable-wallpaper")
        preferences.setSpaceRule(legacyRule, for: "42001")
        preferences.setSpaceRule(legacyRule, for: "42002")
        preferences.setSpaceRule(stableRule, for: "stable-space-id")

        let spaces = [
            SpaceDescriptor(
                id: "ambiguous-a",
                name: "Work",
                displayID: "display-1",
                displayName: "Built-in Display",
                number: 1,
                isFullscreen: false,
                managedSpaceID: "42001"
            ),
            SpaceDescriptor(
                id: "ambiguous-b",
                name: "Personal",
                displayID: "display-1",
                displayName: "Built-in Display",
                number: 2,
                isFullscreen: false,
                managedSpaceID: "42001"
            ),
            SpaceDescriptor(
                id: "stable-space-id",
                name: "Research",
                displayID: "display-2",
                displayName: "External Display",
                number: 1,
                isFullscreen: false,
                managedSpaceID: "42002"
            )
        ]

        XCTAssertEqual(preferences.migrateLegacySpaceOverrides(using: spaces), 0)
        XCTAssertEqual(preferences.spaceRule(for: "42001"), legacyRule)
        XCTAssertEqual(preferences.spaceRule(for: "42002"), legacyRule)
        XCTAssertEqual(preferences.spaceRule(for: "stable-space-id"), stableRule)
    }
}
