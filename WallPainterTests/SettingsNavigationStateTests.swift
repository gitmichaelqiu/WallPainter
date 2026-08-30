import XCTest

@testable import WallPainter

@MainActor
final class SettingsNavigationStateTests: XCTestCase {
    func testRegisterKeepsEachSettingSearchable() async {
        let state = SettingsNavigationState()

        state.register(title: "Current desktop wallpaper", tab: .general)
        state.register(title: "Status", tab: .general)
        state.register(title: "Refresh catalog", tab: .general)
        await drainMainQueue()

        XCTAssertEqual(
            state.registeredItems.map(\.title),
            ["Current desktop wallpaper", "Status", "Refresh catalog"]
        )
        XCTAssertEqual(state.registeredItems.map(\.tab), [.general, .general, .general])
        XCTAssertEqual(Set(state.registeredItems.map(\.id)).count, 3)
    }

    func testDuplicateRegistrationIsRemovedAfterFinalUnregister() async {
        let state = SettingsNavigationState()

        state.register(title: "Status", tab: .general)
        state.register(title: "Status", tab: .general)
        await drainMainQueue()
        XCTAssertEqual(state.registeredItems.count, 1)

        state.unregister(title: "Status", tab: .general)
        await drainMainQueue()
        XCTAssertEqual(state.registeredItems.count, 1)

        state.unregister(title: "Status", tab: .general)
        await drainMainQueue()
        XCTAssertTrue(state.registeredItems.isEmpty)
    }

    func testSettingsCanRegisterItemsAcrossEveryTab() async {
        let state = SettingsNavigationState()

        state.register(title: "Current wallpaper", tab: .general)
        state.register(title: "Enable Automatic Switching", tab: .automation)
        state.register(title: "GitHub / Support", tab: .about)
        await drainMainQueue()

        XCTAssertEqual(
            Set(state.registeredItems.map(\.tab)),
            Set(SettingsTab.allCases)
        )
    }

    private func drainMainQueue() async {
        let expectation = expectation(description: "Main queue drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1)
    }
}
