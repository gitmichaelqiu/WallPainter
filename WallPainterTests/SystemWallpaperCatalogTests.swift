import Foundation
import XCTest

@testable import WallPainter

final class SystemWallpaperCatalogTests: XCTestCase {
    func testCatalogUsesLocalizedNamesAndDisambiguatesDuplicates() throws {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WallPainterCatalogTests-\(UUID().uuidString)", isDirectory: true)
        let aerialDirectory = supportDirectory
            .appendingPathComponent("com.apple.wallpaper/aerials", isDirectory: true)
        let videoDirectory = aerialDirectory.appendingPathComponent("videos", isDirectory: true)
        let manifestDirectory = aerialDirectory.appendingPathComponent("manifest", isDirectory: true)

        try fileManager.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: supportDirectory) }

        let assets: [[String: Any]] = [
            [
                "id": "dynamic-light",
                "accessibilityLabel": "macOS",
                "localizedNameKey": "DYNAMIC_LIGHT_KEY",
                "preferredOrder": 0,
                "shotID": "GG_LM_H",
                "variant": ["appearance": "light", "orientation": "landscape"]
            ],
            [
                "id": "dynamic-light-portrait",
                "accessibilityLabel": "macOS",
                "localizedNameKey": "DYNAMIC_LIGHT_KEY",
                "preferredOrder": 1,
                "shotID": "GG_LM_V",
                "variant": ["appearance": "light", "orientation": "portrait"]
            ],
            [
                "id": "golden-gate-day",
                "accessibilityLabel": "GG_A_DAY_BLUFFS_C35_V25_HFR_HEVC",
                "localizedNameKey": "GG_A_DAY_NAME",
                "preferredOrder": 2,
                "shotID": "GG_A_DAY"
            ],
            [
                "id": "grand-canyon-one",
                "accessibilityLabel": "Grand Canyon",
                "localizedNameKey": "GRAND_CANYON_ONE",
                "preferredOrder": 3,
                "shotID": "G010_C026_0107KE"
            ],
            [
                "id": "grand-canyon-two",
                "accessibilityLabel": "Grand Canyon",
                "localizedNameKey": "GRAND_CANYON_TWO",
                "preferredOrder": 4,
                "shotID": "G007_C004"
            ]
        ]

        let manifestData = try JSONSerialization.data(
            withJSONObject: ["assets": assets],
            options: []
        )
        try manifestData.write(
            to: manifestDirectory.appendingPathComponent("entries.json")
        )

        for asset in assets {
            let id = try XCTUnwrap(asset["id"] as? String)
            try Data().write(to: videoDirectory.appendingPathComponent("\(id).mov"))
        }

        let localizer = TestWallpaperNameLocalizer(names: [
            "DYNAMIC_LIGHT_KEY": "Light",
            "GG_A_DAY_NAME": "Golden Gate Day",
            "GRAND_CANYON_ONE": "Grand Canyon",
            "GRAND_CANYON_TWO": "Grand Canyon"
        ])
        let catalog = SystemWallpaperCatalog(
            fileManager: fileManager,
            applicationSupportDirectory: supportDirectory,
            nameLocalizer: localizer
        )

        let items = try catalog.installedAerials()

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.name) }),
            [
                "dynamic-light": "macOS Light (Landscape)",
                "dynamic-light-portrait": "macOS Light (Portrait)",
                "golden-gate-day": "Golden Gate Day",
                "grand-canyon-one": "Grand Canyon (1)",
                "grand-canyon-two": "Grand Canyon (2)"
            ]
        )
    }
}

private struct TestWallpaperNameLocalizer: WallpaperNameLocalizing {
    let names: [String: String]

    func localizedString(forKey key: String) -> String? {
        names[key]
    }
}
