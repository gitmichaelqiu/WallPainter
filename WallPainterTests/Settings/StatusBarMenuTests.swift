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

    func testEntriesReportMixedStateAcrossActiveSpaces() {
        let wallpapers = [
            makeWallpaper(id: "day", name: "Golden Gate Day"),
            makeWallpaper(id: "night", name: "Golden Gate Night")
        ]
        let activeTargets = [
            WallpaperSpaceTarget(spaceID: "space-1", displayID: "display-1"),
            WallpaperSpaceTarget(spaceID: "space-2", displayID: "display-2")
        ]

        let entries = WallpaperMenuEntries.make(
            wallpapers: wallpapers,
            currentWallpaperIDsBySpaceID: [
                "space-1": "day",
                "space-2": "night"
            ],
            activeSpaceTargets: activeTargets,
            isSpaceAPIAvailable: true
        )

        XCTAssertEqual(entries.map(\.state), [.mixed, .mixed])
    }

    func testEntriesAreDisabledWhenSpaceAPIHasNoActiveSpace() {
        let wallpapers = [makeWallpaper(id: "day", name: "Golden Gate Day")]

        let entries = WallpaperMenuEntries.make(
            wallpapers: wallpapers,
            currentWallpaperIDsBySpaceID: [:],
            activeSpaceTargets: [],
            isSpaceAPIAvailable: false
        )

        XCTAssertEqual(entries.map(\.state), [.disabled])
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
