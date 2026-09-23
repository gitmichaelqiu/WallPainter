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
            ],
            [
                "id": "greenland-evening",
                "accessibilityLabel": "Greenland",
                "localizedNameKey": "GL_G010_C006_NAME",
                "preferredOrder": 5,
                "shotID": "GL_G010_C006"
            ],
            [
                "id": "greenland-coast",
                "accessibilityLabel": "Greenland",
                "localizedNameKey": "GL_G002_C002_NAME",
                "preferredOrder": 6,
                "shotID": "GL_G002_C002"
            ],
            [
                "id": "greenland-glacier",
                "accessibilityLabel": "Greenland",
                "localizedNameKey": "GL_G004_C010_NAME",
                "preferredOrder": 7,
                "shotID": "GL_G004_C010"
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
            "GRAND_CANYON_TWO": "Grand Canyon",
            "GL_G010_C006_NAME": "Greenland Evening",
            "GL_G002_C002_NAME": "Greenland Coast",
            "GL_G004_C010_NAME": "Greenland Glacier"
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
                "grand-canyon-two": "Grand Canyon (2)",
                "greenland-evening": "Greenland Evening",
                "greenland-coast": "Greenland Coast",
                "greenland-glacier": "Greenland Glacier"
            ]
        )
    }

    func testBundleWallpaperNameLocalizerReadsNoCacheTableAndMatchesPreferredLanguage() throws {
        let tableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WallPainterNames-\(UUID().uuidString).loctable")
        defer { try? FileManager.default.removeItem(at: tableURL) }

        let translations = [
            "en": ["GREENLAND_EVENING": "Greenland Evening"],
            "fr": ["GREENLAND_EVENING": "Soir au Groenland"]
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: translations,
            format: .binary,
            options: 0
        )
        try data.write(to: tableURL)

        let localizer = BundleWallpaperNameLocalizer(
            localizationTableURL: tableURL,
            languagePreferences: ["fr-CA", "en-US"]
        )

        XCTAssertEqual(
            localizer.localizedString(forKey: "GREENLAND_EVENING"),
            "Soir au Groenland"
        )
    }

    func testSystemBundleResolvesDistinctGreenlandNamesWhenAvailable() throws {
        let bundle = Bundle(
            path: "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources/TVIdleScreenStrings.bundle"
        )
        guard let tableURL = bundle?.resourceURL?
            .appendingPathComponent("Localizable.nocache.loctable"),
              FileManager.default.fileExists(atPath: tableURL.path)
        else {
            throw XCTSkip("The system Aerial name table is unavailable on this macOS version.")
        }

        let localizer = BundleWallpaperNameLocalizer(
            bundle: bundle,
            languagePreferences: ["en-US"]
        )
        let names = [
            "GL_G010_C006_NAME",
            "GL_G002_C002_NAME",
            "GL_G004_C010_NAME"
        ].compactMap(localizer.localizedString(forKey:))

        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(Set(names), ["Greenland Evening", "Greenland Coast", "Greenland Glacier"])
    }
}

private struct TestWallpaperNameLocalizer: WallpaperNameLocalizing {
    let names: [String: String]

    func localizedString(forKey key: String) -> String? {
        names[key]
    }
}
