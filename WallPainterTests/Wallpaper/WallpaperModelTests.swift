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

    func testApplyWallpaperToTargetsUpdatesOnlyThoseTargets() {
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let wallpaper = WallpaperItem.preview
        let target = WallpaperSpaceTarget(spaceID: "space-1", displayID: "display-1")
        let store = ScopedRecordingWallpaperStore(currentIDs: ["space-1": "old-aerial"])
        let model = WallpaperModel(
            catalog: TestWallpaperCatalog(items: [wallpaper]),
            store: store,
            preferences: preferences
        )
        model.setActiveSpaceTargets([target])
        model.refresh()

        XCTAssertTrue(model.applyWallpaper(id: wallpaper.id, to: [target]))
        XCTAssertEqual(store.appliedMaps, [["space-1": wallpaper.id]])
        XCTAssertEqual(model.currentWallpaperIDsBySpaceID, ["space-1": wallpaper.id])
        XCTAssertEqual(model.currentWallpaperID, wallpaper.id)
    }

    func testApplyWallpaperToTargetsDoesNotWriteWhenAllTargetsAlreadyMatch() {
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let wallpaper = WallpaperItem.preview
        let target = WallpaperSpaceTarget(spaceID: "space-1", displayID: "display-1")
        let store = ScopedRecordingWallpaperStore(currentIDs: ["space-1": wallpaper.id])
        let model = WallpaperModel(
            catalog: TestWallpaperCatalog(items: [wallpaper]),
            store: store,
            preferences: preferences
        )
        model.setActiveSpaceTargets([target])
        model.refresh()

        XCTAssertTrue(model.applyWallpaper(id: wallpaper.id, to: [target]))
        XCTAssertTrue(store.appliedMaps.isEmpty)
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

@MainActor
private final class ScopedRecordingWallpaperStore: WallpaperStoring {
    var currentIDs: [String: String]
    private(set) var appliedMaps: [[String: String]] = []

    init(currentIDs: [String: String]) {
        self.currentIDs = currentIDs
    }

    func currentAerialID() throws -> String? {
        currentIDs.values.first
    }

    func setAerialWallpaper(assetID: String) throws {
        for spaceID in currentIDs.keys {
            currentIDs[spaceID] = assetID
        }
    }

    func currentAerialIDs(for targets: [WallpaperSpaceTarget]) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: targets.compactMap { target in
            guard let wallpaperID = currentIDs[target.spaceID] else { return nil }
            return (target.spaceID, wallpaperID)
        })
    }

    func setAerialWallpapers(
        _ wallpaperIDsBySpaceID: [String: String],
        for targets: [WallpaperSpaceTarget]
    ) throws {
        appliedMaps.append(wallpaperIDsBySpaceID)
        currentIDs.merge(wallpaperIDsBySpaceID) { _, new in new }
    }
}
