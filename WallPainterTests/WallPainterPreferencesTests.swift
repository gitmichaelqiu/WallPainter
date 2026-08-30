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
}
