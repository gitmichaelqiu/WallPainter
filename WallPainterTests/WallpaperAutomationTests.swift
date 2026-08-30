import XCTest

@testable import WallPainter

@MainActor
final class WallpaperAutomationTests: XCTestCase {
    func testPreferencesUseWallPainterDefaults() {
        let preferences = WallPainterPreferences(defaults: makeDefaults())

        XCTAssertNil(preferences.selectedWallpaperID)
        XCTAssertTrue(preferences.showStatusBarItem)
        XCTAssertFalse(preferences.automationEnabled)
        XCTAssertNil(preferences.automationLightWallpaperID)
        XCTAssertNil(preferences.automationDarkWallpaperID)
    }

    func testAutomationDisablesUntilBothMappingsAreInstalled() {
        let preferences = makePreferences()
        let wallpaper = makeWallpaper(id: "light")
        preferences.automationLightWallpaperID = wallpaper.id
        preferences.automationEnabled = true

        let store = AutomationTestWallpaperStore(currentID: nil)
        let model = makeModel(items: [wallpaper], store: store, preferences: preferences)
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: AutomationTestAppearanceMonitor(initialAppearance: .light)
        )
        coordinator.start()

        XCTAssertFalse(preferences.automationEnabled)
        XCTAssertTrue(store.appliedIDs.isEmpty)
    }

    func testAutomationAppliesTheLightAndDarkMappings() {
        let light = makeWallpaper(id: "light")
        let dark = makeWallpaper(id: "dark")
        let preferences = makePreferences()
        preferences.automationLightWallpaperID = light.id
        preferences.automationDarkWallpaperID = dark.id
        preferences.automationEnabled = true

        let store = AutomationTestWallpaperStore(currentID: "other")
        let model = makeModel(
            items: [light, dark],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let monitor = AutomationTestAppearanceMonitor(initialAppearance: .light)
        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: monitor
        )
        coordinator.start()

        XCTAssertEqual(store.appliedIDs, [light.id])
        XCTAssertEqual(model.selectedWallpaperID, light.id)
        XCTAssertEqual(model.currentWallpaperID, light.id)

        monitor.emit(.dark)

        XCTAssertEqual(store.appliedIDs, [light.id, dark.id])
        XCTAssertEqual(model.selectedWallpaperID, dark.id)
        XCTAssertEqual(model.currentWallpaperID, dark.id)
    }

    func testEnablingAndChangingTheActiveMappingApplyImmediately() async {
        let light = makeWallpaper(id: "light")
        let replacement = makeWallpaper(id: "light-replacement")
        let dark = makeWallpaper(id: "dark")
        let preferences = makePreferences()
        preferences.automationLightWallpaperID = light.id
        preferences.automationDarkWallpaperID = dark.id

        let store = AutomationTestWallpaperStore(currentID: "other")
        let catalog = AutomationTestWallpaperCatalog(items: [light, replacement, dark])
        let model = WallpaperModel(
            catalog: catalog,
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: AutomationTestAppearanceMonitor(initialAppearance: .light)
        )
        coordinator.start()
        XCTAssertTrue(store.appliedIDs.isEmpty)

        preferences.automationEnabled = true
        await drainMainQueue()
        XCTAssertEqual(store.appliedIDs, [light.id])

        preferences.automationLightWallpaperID = replacement.id
        await drainMainQueue()
        XCTAssertEqual(store.appliedIDs, [light.id, replacement.id])
    }

    func testAutomationDoesNotWriteWhenTargetIsAlreadyCurrent() {
        let light = makeWallpaper(id: "light")
        let dark = makeWallpaper(id: "dark")
        let preferences = makePreferences()
        preferences.automationLightWallpaperID = light.id
        preferences.automationDarkWallpaperID = dark.id
        preferences.automationEnabled = true

        let store = AutomationTestWallpaperStore(currentID: light.id)
        let model = makeModel(
            items: [light, dark],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: AutomationTestAppearanceMonitor(initialAppearance: .light)
        )
        coordinator.start()

        XCTAssertTrue(store.appliedIDs.isEmpty)
        XCTAssertEqual(model.selectedWallpaperID, light.id)
    }

    func testMissingMappingDisablesAutomationButRetainsSavedIDs() async {
        let light = makeWallpaper(id: "light")
        let dark = makeWallpaper(id: "dark")
        let preferences = makePreferences()
        preferences.automationLightWallpaperID = light.id
        preferences.automationDarkWallpaperID = dark.id
        preferences.automationEnabled = true

        let store = AutomationTestWallpaperStore(currentID: light.id)
        let catalog = AutomationTestWallpaperCatalog(items: [light, dark])
        let model = WallpaperModel(
            catalog: catalog,
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: AutomationTestAppearanceMonitor(initialAppearance: .light)
        )
        coordinator.start()

        catalog.items = [light]
        model.refresh()
        await drainMainQueue()

        XCTAssertFalse(preferences.automationEnabled)
        XCTAssertEqual(preferences.automationLightWallpaperID, light.id)
        XCTAssertEqual(preferences.automationDarkWallpaperID, dark.id)
    }

    func testFailedStoreWriteLeavesAutomationEnabledAndSelectionUnchanged() {
        let light = makeWallpaper(id: "light")
        let dark = makeWallpaper(id: "dark")
        let preferences = makePreferences()
        preferences.selectedWallpaperID = dark.id
        preferences.automationLightWallpaperID = light.id
        preferences.automationDarkWallpaperID = dark.id
        preferences.automationEnabled = true

        let store = AutomationTestWallpaperStore(
            currentID: "other",
            error: TestStoreError()
        )
        let model = makeModel(
            items: [light, dark],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: AutomationTestAppearanceMonitor(initialAppearance: .light)
        )
        coordinator.start()

        XCTAssertEqual(store.appliedIDs, [light.id])
        XCTAssertEqual(model.selectedWallpaperID, dark.id)
        XCTAssertEqual(model.currentWallpaperID, "other")
        XCTAssertTrue(preferences.automationEnabled)
        XCTAssertEqual(model.operationStatus?.isSuccess, false)
    }

    func testEmptyCatalogCannotEnableAutomation() {
        let preferences = makePreferences()
        preferences.automationLightWallpaperID = "light"
        preferences.automationDarkWallpaperID = "dark"
        preferences.automationEnabled = true

        let store = AutomationTestWallpaperStore(currentID: nil)
        let model = makeModel(items: [], store: store, preferences: preferences)
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: AutomationTestAppearanceMonitor(initialAppearance: .dark)
        )
        coordinator.start()

        XCTAssertFalse(coordinator.hasValidMappings)
        XCTAssertFalse(preferences.automationEnabled)
        XCTAssertTrue(store.appliedIDs.isEmpty)
    }

    private func makePreferences() -> WallPainterPreferences {
        WallPainterPreferences(defaults: makeDefaults())
    }

    private func makeModel(
        items: [WallpaperItem],
        store: AutomationTestWallpaperStore,
        preferences: WallPainterPreferences
    ) -> WallpaperModel {
        WallpaperModel(
            catalog: AutomationTestWallpaperCatalog(items: items),
            store: store,
            preferences: preferences
        )
    }

    private func makeWallpaper(id: String) -> WallpaperItem {
        WallpaperItem(
            id: id,
            name: id.capitalized,
            thumbnailURL: nil,
            videoURL: URL(fileURLWithPath: "/tmp/\(id).mov"),
            preferredOrder: 0
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WallPainterAutomationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func drainMainQueue() async {
        let expectation = expectation(description: "Main queue drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1)
    }
}

@MainActor
private final class AutomationTestAppearanceMonitor: AppearanceMonitoring {
    let initialAppearance: WallpaperAppearance
    private var handler: ((WallpaperAppearance) -> Void)?

    init(initialAppearance: WallpaperAppearance) {
        self.initialAppearance = initialAppearance
    }

    func start(handler: @escaping (WallpaperAppearance) -> Void) {
        self.handler = handler
        handler(initialAppearance)
    }

    func stop() {
        handler = nil
    }

    func emit(_ appearance: WallpaperAppearance) {
        handler?(appearance)
    }
}

@MainActor
private final class AutomationTestWallpaperCatalog: WallpaperCatalogProviding {
    var items: [WallpaperItem]

    init(items: [WallpaperItem]) {
        self.items = items
    }

    func installedAerials() throws -> [WallpaperItem] {
        items
    }
}

@MainActor
private final class AutomationTestWallpaperStore: WallpaperStoring {
    var currentID: String?
    let error: Error?
    private(set) var appliedIDs: [String] = []

    init(currentID: String?, error: Error? = nil) {
        self.currentID = currentID
        self.error = error
    }

    func currentAerialID() throws -> String? {
        currentID
    }

    func setAerialWallpaper(assetID: String) throws {
        appliedIDs.append(assetID)
        if let error {
            throw error
        }
        currentID = assetID
    }
}

private struct TestStoreError: LocalizedError {
    var errorDescription: String? { "Test wallpaper write failed." }
}
