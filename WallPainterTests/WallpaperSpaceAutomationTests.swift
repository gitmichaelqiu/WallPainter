import XCTest

@testable import WallPainter

@MainActor
final class WallpaperSpaceAutomationTests: XCTestCase {
    func testAutomationAppliesIndependentRulesAcrossActiveDisplays() {
        let light = makeWallpaper(id: "light")
        let dark = makeWallpaper(id: "dark")
        let fixed = makeWallpaper(id: "fixed")
        let preferences = makePreferences()
        preferences.automationDefaultRule = .appearance(
            lightWallpaperID: light.id,
            darkWallpaperID: dark.id
        )
        preferences.setSpaceRule(.fixed(fixed.id), for: "space-b")
        preferences.automationEnabled = true

        let store = SpaceAutomationTestStore(
            currentIDs: ["space-a": "old-a", "space-b": "old-b"]
        )
        let provider = SpaceAutomationTestProvider(
            snapshot: makeSnapshot(currentSpaceIDs: ["space-a", "space-b"]),
            isAvailable: true
        )
        let model = makeModel(
            items: [light, dark, fixed],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: SpaceAutomationTestAppearanceMonitor(initialAppearance: .light),
            spaceProvider: provider
        )
        coordinator.start()

        XCTAssertEqual(
            store.scopedWrites,
            [["space-a": light.id, "space-b": fixed.id]]
        )
        XCTAssertTrue(store.globalWrites.isEmpty)
        XCTAssertEqual(
            model.activeSpaceTargets,
            [
                WallpaperSpaceTarget(spaceID: "space-a", displayID: "display-1"),
                WallpaperSpaceTarget(spaceID: "space-b", displayID: "display-2")
            ]
        )

        XCTAssertEqual(model.currentWallpaperState, .mixed)
    }

    func testAppearanceChangeWritesOnlySpacesThatNeedChanging() {
        let light = makeWallpaper(id: "light")
        let dark = makeWallpaper(id: "dark")
        let fixed = makeWallpaper(id: "fixed")
        let preferences = makePreferences()
        preferences.automationDefaultRule = .appearance(
            lightWallpaperID: light.id,
            darkWallpaperID: dark.id
        )
        preferences.setSpaceRule(.fixed(fixed.id), for: "space-b")
        preferences.automationEnabled = true

        let store = SpaceAutomationTestStore(
            currentIDs: ["space-a": "old-a", "space-b": "old-b"]
        )
        let monitor = SpaceAutomationTestAppearanceMonitor(initialAppearance: .light)
        let model = makeModel(
            items: [light, dark, fixed],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: monitor,
            spaceProvider: SpaceAutomationTestProvider(
                snapshot: makeSnapshot(currentSpaceIDs: ["space-a", "space-b"]),
                isAvailable: true
            )
        )
        coordinator.start()
        monitor.emit(.dark)

        XCTAssertEqual(
            store.scopedWrites,
            [
                ["space-a": light.id, "space-b": fixed.id],
                ["space-a": dark.id]
            ]
        )
        XCTAssertEqual(model.currentWallpaperState, .mixed)
    }

    func testAutomationDoesNotWriteWhenAllTargetsAlreadyMatch() {
        let wallpaper = makeWallpaper(id: "wallpaper")
        let preferences = makePreferences()
        preferences.automationDefaultRule = .fixed(wallpaper.id)
        preferences.automationEnabled = true

        let store = SpaceAutomationTestStore(
            currentIDs: ["space-a": wallpaper.id, "space-b": wallpaper.id]
        )
        let model = makeModel(
            items: [wallpaper],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: SpaceAutomationTestAppearanceMonitor(initialAppearance: .dark),
            spaceProvider: SpaceAutomationTestProvider(
                snapshot: makeSnapshot(currentSpaceIDs: ["space-a", "space-b"]),
                isAvailable: true
            )
        )
        coordinator.start()

        XCTAssertTrue(store.scopedWrites.isEmpty)
        XCTAssertTrue(store.globalWrites.isEmpty)
        XCTAssertEqual(model.currentWallpaperState, .uniform(wallpaper.id))
    }

    func testUnavailableSpaceAPIPausesWithoutGlobalFallback() {
        let wallpaper = makeWallpaper(id: "wallpaper")
        let preferences = makePreferences()
        preferences.automationDefaultRule = .fixed(wallpaper.id)
        preferences.automationEnabled = true

        let store = SpaceAutomationTestStore(currentIDs: ["space-a": "old"])
        let model = makeModel(
            items: [wallpaper],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: SpaceAutomationTestAppearanceMonitor(initialAppearance: .light),
            spaceProvider: SpaceAutomationTestProvider(
                snapshot: makeSnapshot(currentSpaceIDs: ["space-a"]),
                isAvailable: false
            )
        )
        coordinator.start()

        XCTAssertTrue(preferences.automationEnabled)
        XCTAssertTrue(store.scopedWrites.isEmpty)
        XCTAssertTrue(store.globalWrites.isEmpty)
    }

    func testInvalidSpaceOverrideIsSkippedWhileDefaultRuleContinues() {
        let wallpaper = makeWallpaper(id: "wallpaper")
        let preferences = makePreferences()
        preferences.automationDefaultRule = .fixed(wallpaper.id)
        preferences.setSpaceRule(.appearance(
            lightWallpaperID: "missing-light",
            darkWallpaperID: "missing-dark"
        ), for: "space-b")
        preferences.automationEnabled = true

        let store = SpaceAutomationTestStore(
            currentIDs: ["space-a": "old-a", "space-b": "old-b"]
        )
        let model = makeModel(
            items: [wallpaper],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: SpaceAutomationTestAppearanceMonitor(initialAppearance: .light),
            spaceProvider: SpaceAutomationTestProvider(
                snapshot: makeSnapshot(currentSpaceIDs: ["space-a", "space-b"]),
                isAvailable: true
            )
        )
        coordinator.start()

        XCTAssertEqual(store.scopedWrites, [["space-a": wallpaper.id]])
        XCTAssertEqual(preferences.spaceRule(for: "space-b")?.mode, .appearance)
    }

    func testSpaceChangeReconcilesNewlyActiveSpaces() async {
        let wallpaper = makeWallpaper(id: "wallpaper")
        let preferences = makePreferences()
        preferences.automationDefaultRule = .fixed(wallpaper.id)
        preferences.automationEnabled = true

        let store = SpaceAutomationTestStore(
            currentIDs: ["space-a": "old-a", "space-b": "old-b"]
        )
        let provider = SpaceAutomationTestProvider(
            snapshot: makeSnapshot(currentSpaceIDs: ["space-a"]),
            isAvailable: true
        )
        let model = makeModel(
            items: [wallpaper],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: SpaceAutomationTestAppearanceMonitor(initialAppearance: .light),
            spaceProvider: provider
        )
        coordinator.start()

        provider.update(snapshot: makeSnapshot(currentSpaceIDs: ["space-b"]))
        await drainMainQueue()

        XCTAssertEqual(
            model.activeSpaceTargets,
            [WallpaperSpaceTarget(spaceID: "space-b", displayID: "display-2")]
        )
        XCTAssertEqual(store.scopedWrites, [["space-a": wallpaper.id, "space-b": wallpaper.id]])
    }

    func testInvalidAllSpacesRuleDisablesAutomationAndRetainsRule() {
        let preferences = makePreferences()
        preferences.automationDefaultRule = .fixed("missing")
        preferences.automationEnabled = true

        let store = SpaceAutomationTestStore(currentIDs: ["space-a": "old"])
        let model = makeModel(
            items: [makeWallpaper(id: "installed")],
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: SpaceAutomationTestAppearanceMonitor(initialAppearance: .light),
            spaceProvider: SpaceAutomationTestProvider(
                snapshot: makeSnapshot(currentSpaceIDs: ["space-a"]),
                isAvailable: true
            )
        )
        coordinator.start()

        XCTAssertFalse(preferences.automationEnabled)
        XCTAssertEqual(preferences.automationDefaultRule, .fixed("missing"))
        XCTAssertTrue(store.scopedWrites.isEmpty)
    }

    private func makeModel(
        items: [WallpaperItem],
        store: SpaceAutomationTestStore,
        preferences: WallPainterPreferences
    ) -> WallpaperModel {
        WallpaperModel(
            catalog: SpaceAutomationTestCatalog(items: items),
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

    private func makePreferences() -> WallPainterPreferences {
        let suiteName = "WallPainterSpaceAutomationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return WallPainterPreferences(defaults: defaults)
    }

    private func makeSnapshot(currentSpaceIDs: [String]) -> SpaceSnapshot {
        SpaceSnapshot(
            revision: 1,
            currentSpaceIDs: currentSpaceIDs,
            spaces: [
                SpaceDescriptor(
                    id: "space-a",
                    name: "Writing",
                    displayID: "display-1",
                    displayName: "Built-in Display",
                    number: 1,
                    isFullscreen: false
                ),
                SpaceDescriptor(
                    id: "space-b",
                    name: "Research",
                    displayID: "display-2",
                    displayName: "External Display",
                    number: 2,
                    isFullscreen: false
                ),
                SpaceDescriptor(
                    id: "full-screen",
                    name: "Video",
                    displayID: "display-1",
                    displayName: "Built-in Display",
                    number: 0,
                    isFullscreen: true
                )
            ]
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

@MainActor
private final class SpaceAutomationTestProvider: SpaceAPIProviding {
    private(set) var snapshot: SpaceSnapshot?
    private(set) var isAvailable: Bool

    init(snapshot: SpaceSnapshot?, isAvailable: Bool) {
        self.snapshot = snapshot
        self.isAvailable = isAvailable
    }

    func start() {}

    func stop() {}

    func refresh() {}

    func update(snapshot: SpaceSnapshot, isAvailable: Bool = true) {
        self.snapshot = snapshot
        self.isAvailable = isAvailable
        NotificationCenter.default.post(
            name: .wallPainterSpaceSnapshotDidChange,
            object: self
        )
        NotificationCenter.default.post(
            name: .wallPainterSpaceAvailabilityDidChange,
            object: self
        )
    }
}

@MainActor
private final class SpaceAutomationTestAppearanceMonitor: AppearanceMonitoring {
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
private final class SpaceAutomationTestCatalog: WallpaperCatalogProviding {
    let items: [WallpaperItem]

    init(items: [WallpaperItem]) {
        self.items = items
    }

    func installedAerials() throws -> [WallpaperItem] {
        items
    }
}

@MainActor
private final class SpaceAutomationTestStore: WallpaperStoring {
    private(set) var currentIDs: [String: String]
    private(set) var scopedWrites: [[String: String]] = []
    private(set) var globalWrites: [String] = []

    init(currentIDs: [String: String]) {
        self.currentIDs = currentIDs
    }

    func currentAerialID() throws -> String? {
        currentIDs.values.first
    }

    func currentAerialIDs(for targets: [WallpaperSpaceTarget]) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: targets.compactMap { target in
            guard let wallpaperID = currentIDs[target.spaceID] else { return nil }
            return (target.spaceID, wallpaperID)
        })
    }

    func setAerialWallpaper(assetID: String) throws {
        globalWrites.append(assetID)
        for spaceID in currentIDs.keys {
            currentIDs[spaceID] = assetID
        }
    }

    func setAerialWallpapers(
        _ wallpaperIDsBySpaceID: [String: String],
        for targets: [WallpaperSpaceTarget]
    ) throws {
        scopedWrites.append(wallpaperIDsBySpaceID)
        for target in targets {
            if let wallpaperID = wallpaperIDsBySpaceID[target.spaceID] {
                currentIDs[target.spaceID] = wallpaperID
            }
        }
    }
}
