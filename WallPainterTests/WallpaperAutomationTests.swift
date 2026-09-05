import XCTest

@testable import WallPainter

@MainActor
final class WallpaperAutomationTests: XCTestCase {
    func testPreferencesStartWithManualDefaultRule() {
        let preferences = WallPainterPreferences(defaults: makeDefaults())

        XCTAssertNil(preferences.selectedWallpaperID)
        XCTAssertTrue(preferences.showStatusBarItem)
        XCTAssertEqual(preferences.defaultWallpaperRule, .manual)
        XCTAssertTrue(preferences.defaultWallpaperRule.isValid(installedWallpaperIDs: []))
        XCTAssertNil(preferences.defaultWallpaperRule.resolvedWallpaperID(for: .light))
    }

    func testManualDefaultRuleDoesNotWriteAutomatically() {
        let wallpaper = makeWallpaper(id: "wallpaper")
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let store = AutomationTestWallpaperStore(currentID: "other")
        let model = WallpaperModel(
            catalog: AutomationTestWallpaperCatalog(items: [wallpaper]),
            store: store,
            preferences: preferences
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: AutomationTestAppearanceMonitor(initialAppearance: .light),
            spaceProvider: AutomationTestSpaceProvider()
        )
        coordinator.start()

        XCTAssertTrue(store.appliedIDs.isEmpty)
        XCTAssertTrue(store.scopedWrites.isEmpty)
    }

    func testDefaultAppearanceRuleResolvesToInstalledMapping() {
        let light = makeWallpaper(id: "light")
        let dark = makeWallpaper(id: "dark")
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        preferences.defaultWallpaperRule = .appearance(
            lightWallpaperID: light.id,
            darkWallpaperID: dark.id
        )

        XCTAssertEqual(
            preferences.defaultWallpaperRule.resolvedWallpaperID(for: .light),
            light.id
        )
        XCTAssertEqual(
            preferences.defaultWallpaperRule.resolvedWallpaperID(for: .dark),
            dark.id
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
}

@MainActor
private final class AutomationTestSpaceProvider: SpaceAPIProviding {
    var snapshot: SpaceSnapshot? = SpaceSnapshot(
        revision: 1,
        currentSpaceIDs: ["space-1"],
        spaces: [
            SpaceDescriptor(
                id: "space-1",
                name: "Main",
                displayID: "display-1",
                displayName: "Built-in Display",
                number: 1,
                isFullscreen: false
            )
        ]
    )
    var isAvailable = true

    func start() {}
    func stop() {}
    func refresh() {}
}

@MainActor
private final class AutomationTestAppearanceMonitor: AppearanceMonitoring {
    let initialAppearance: WallpaperAppearance

    init(initialAppearance: WallpaperAppearance) {
        self.initialAppearance = initialAppearance
    }

    func start(handler: @escaping (WallpaperAppearance) -> Void) {
        handler(initialAppearance)
    }

    func stop() {}
}

@MainActor
private final class AutomationTestWallpaperCatalog: WallpaperCatalogProviding {
    let items: [WallpaperItem]

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
    private(set) var appliedIDs: [String] = []
    private(set) var scopedWrites: [[String: String]] = []

    init(currentID: String?) {
        self.currentID = currentID
    }

    func currentAerialID() throws -> String? {
        currentID
    }

    func setAerialWallpaper(assetID: String) throws {
        appliedIDs.append(assetID)
        currentID = assetID
    }

    func currentAerialIDs(for targets: [WallpaperSpaceTarget]) throws -> [String: String] {
        guard let currentID else { return [:] }
        return Dictionary(uniqueKeysWithValues: targets.map { ($0.spaceID, currentID) })
    }

    func setAerialWallpapers(
        _ wallpaperIDsBySpaceID: [String: String],
        for targets: [WallpaperSpaceTarget]
    ) throws {
        scopedWrites.append(wallpaperIDsBySpaceID)
        if let firstID = wallpaperIDsBySpaceID.values.first {
            currentID = firstID
        }
    }
}
