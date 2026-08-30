import XCTest

@testable import WallPainter

final class StatusBarMenuTests: XCTestCase {
    func testEntriesContainEveryWallpaperAndCheckCurrentWallpaper() {
        let wallpapers = [
            makeWallpaper(id: "day", name: "Golden Gate Day"),
            makeWallpaper(id: "night", name: "Golden Gate Night")
        ]

        let entries = WallpaperMenuEntries.make(
            wallpapers: wallpapers,
            currentWallpaperID: "night"
        )

        XCTAssertEqual(
            entries,
            [
                WallpaperMenuEntry(id: "day", title: "Golden Gate Day", isCurrent: false),
                WallpaperMenuEntry(id: "night", title: "Golden Gate Night", isCurrent: true)
            ]
        )
    }

    func testEmptyCatalogProducesNoSwitchEntries() {
        XCTAssertTrue(
            WallpaperMenuEntries.make(wallpapers: [], currentWallpaperID: nil).isEmpty
        )
    }

    private func makeWallpaper(id: String, name: String) -> WallpaperItem {
        WallpaperItem(
            id: id,
            name: name,
            thumbnailURL: nil,
            videoURL: URL(fileURLWithPath: "/tmp/\(id).mov"),
            preferredOrder: 0
        )
    }
}
