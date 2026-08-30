import XCTest

@testable import WallPainter

@MainActor
final class WallpaperModelTests: XCTestCase {
    func testApplyWallpaperUpdatesSelectionAndCurrentWallpaper() {
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let wallpaper = WallpaperItem(
            id: "aerial-2",
            name: "Golden Gate Night",
            thumbnailURL: nil,
            videoURL: URL(fileURLWithPath: "/tmp/aerial-2.mov"),
            preferredOrder: 1
        )
        let store = RecordingWallpaperStore(currentID: "aerial-1")
        let model = WallpaperModel(
            catalog: TestWallpaperCatalog(items: [wallpaper]),
            store: store,
            preferences: preferences
        )
        model.refresh()

        XCTAssertTrue(model.applyWallpaper(id: wallpaper.id))
        XCTAssertEqual(model.selectedWallpaperID, wallpaper.id)
        XCTAssertEqual(model.currentWallpaperID, wallpaper.id)
        XCTAssertEqual(store.appliedIDs, [wallpaper.id])
        XCTAssertTrue(model.operationStatus?.isSuccess == true)
    }

    func testApplyWallpaperDoesNotWriteWhenAlreadyCurrent() {
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let wallpaper = WallpaperItem.preview
        let store = RecordingWallpaperStore(currentID: wallpaper.id)
        let model = WallpaperModel(
            catalog: TestWallpaperCatalog(items: [wallpaper]),
            store: store,
            preferences: preferences
        )
        model.refresh()

        XCTAssertTrue(model.applyWallpaper(id: wallpaper.id))
        XCTAssertTrue(store.appliedIDs.isEmpty)
        XCTAssertTrue(model.operationStatus?.isSuccess == true)
    }

    func testApplyWallpaperRejectsUnknownID() {
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let store = RecordingWallpaperStore(currentID: nil)
        let model = WallpaperModel(
            catalog: TestWallpaperCatalog(items: [WallpaperItem.preview]),
            store: store,
            preferences: preferences
        )

        XCTAssertFalse(model.applyWallpaper(id: "missing"))
        XCTAssertTrue(store.appliedIDs.isEmpty)
        XCTAssertEqual(model.operationStatus?.isSuccess, false)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WallPainterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct TestWallpaperCatalog: WallpaperCatalogProviding {
    let items: [WallpaperItem]

    func installedAerials() throws -> [WallpaperItem] {
        items
    }
}

@MainActor
private final class RecordingWallpaperStore: WallpaperStoring {
    var currentID: String?
    private(set) var appliedIDs: [String] = []

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
}
