import XCTest

@testable import WallPainter

@MainActor
final class SettingsNavigationStateTests: XCTestCase {
    func testRegisterKeepsEachSettingSearchable() {
        let state = SettingsNavigationState()

        state.register(title: "Current desktop wallpaper", tab: .wallpaper)
        state.register(title: "Status", tab: .wallpaper)
        state.register(title: "Refresh catalog", tab: .wallpaper)

        XCTAssertEqual(
            state.registeredItems.map(\.title),
            ["Current desktop wallpaper", "Status", "Refresh catalog"]
        )
        XCTAssertEqual(
            state.registeredItems.map(\.id),
            [
                "wallpaper.Current desktop wallpaper",
                "wallpaper.Status",
                "wallpaper.Refresh catalog"
            ]
        )
    }

    func testDuplicateRegistrationIsRemovedAfterFinalUnregister() {
        let state = SettingsNavigationState()

        state.register(title: "Status", tab: .wallpaper)
        state.register(title: "Status", tab: .wallpaper)
        XCTAssertEqual(state.registeredItems.count, 1)

        state.unregister(title: "Status", tab: .wallpaper)
        XCTAssertEqual(state.registeredItems.count, 1)

        state.unregister(title: "Status", tab: .wallpaper)
        XCTAssertTrue(state.registeredItems.isEmpty)
    }
}
