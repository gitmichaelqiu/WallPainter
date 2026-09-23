import Foundation
import XCTest

@testable import WallPainter

@MainActor
final class WallpaperStoreTests: XCTestCase {
    func testCurrentAerialIDDecodesNestedConfiguration() throws {
        let (store, directory, _) = try makeStore(
            choices: [try aerialChoice(assetID: "old-aerial")]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(try store.currentAerialID(), "old-aerial")
    }

    func testSetAerialWallpaperUpdatesEveryAerialChoiceAndReloadsAgent() throws {
        let (store, directory, reloader) = try makeStore(
            choices: [
                try aerialChoice(assetID: "old-aerial-1"),
                imageChoice,
                try aerialChoice(assetID: "old-aerial-2")
            ]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.setAerialWallpaper(assetID: "new-aerial")

        let root = try readStore(at: directory.appendingPathComponent("Index.plist"))
        let spaces = try XCTUnwrap(root["Spaces"] as? [String: Any])
        let space = try XCTUnwrap(spaces["space-1"] as? [String: Any])
        let choices = try XCTUnwrap(space["Choices"] as? [[String: Any]])
        let aerialIDs = choices.compactMap { assetID(from: $0["Configuration"]) }

        XCTAssertEqual(aerialIDs, ["new-aerial", "new-aerial"])
        XCTAssertEqual(choices[1]["Provider"] as? String, "com.apple.wallpaper.choice.image")
        XCTAssertEqual(reloader.reloadCount, 1)
        XCTAssertEqual(try store.currentAerialID(), "new-aerial")
    }

    func testSetAerialWallpaperReportsMissingAerialChoices() throws {
        let (store, directory, reloader) = try makeStore(choices: [imageChoice])
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try store.setAerialWallpaper(assetID: "new-aerial")) { error in
            guard let storeError = error as? WallpaperStoreError,
                  case .noAerialChoices = storeError
            else {
                return XCTFail("Expected noAerialChoices, got \(error)")
            }
        }
        XCTAssertEqual(reloader.reloadCount, 0)
    }

    func testScopedWritePromotesTheTargetChoice() throws {
        let (store, directory, reloader) = try makeStore(choices: [imageChoice])
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = WallpaperSpaceTarget(spaceID: "space-1", displayID: "display-1")
        try store.setAerialWallpapers(["space-1": "new-aerial"], for: [target])

        let root = try readStore(at: directory.appendingPathComponent("Index.plist"))
        let spaces = try XCTUnwrap(root["Spaces"] as? [String: Any])
        let space = try XCTUnwrap(spaces["space-1"] as? [String: Any])
        let choices = try XCTUnwrap(space["Choices"] as? [[String: Any]])

        XCTAssertEqual(choices[0]["Provider"] as? String, "com.apple.wallpaper.choice.aerials")
        XCTAssertEqual(assetID(from: choices[0]["Configuration"]), "new-aerial")
        XCTAssertEqual(reloader.reloadCount, 1)
    }

    func testScopedReadReturnsOnlyRequestedSpaceIDs() throws {
        let (store, directory, _) = try makeStore(
            choices: [try aerialChoice(assetID: "space-aerial")]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = WallpaperSpaceTarget(spaceID: "space-1", displayID: "display-1")

        XCTAssertEqual(
            try store.currentAerialIDs(for: [target]),
            ["space-1": "space-aerial"]
        )
    }

    func testSystemResolverMapsManagedSpaceIDToWallpaperStoreUUID() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("WallPainterSpaceResolverTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let spaces = [
            "SpacesDisplayConfiguration": [
                "Management Data": [
                    "Monitors": [[
                        "Spaces": [[
                            "ManagedSpaceID": 4,
                            "uuid": "wallpaper-space"
                        ]]
                    ]]
                ]
            ]
        ]
        let spacesURL = directory.appendingPathComponent("com.apple.spaces.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: spaces,
            format: .binary,
            options: 0
        )
        try data.write(to: spacesURL)

        let resolver = SystemWallpaperSpaceIDResolver(spacesURL: spacesURL)

        XCTAssertEqual(
            resolver.wallpaperStoreSpaceID(for: "4"),
            "wallpaper-space"
        )
        XCTAssertNil(resolver.wallpaperStoreSpaceID(for: "missing"))
    }

    func testScopedWriteResolvesManagedSpaceIDAndPreservesUnrelatedRecords() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("WallPainterMappedStoreTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let root: [String: Any] = [
            "Displays": [
                "display-1": [
                    "Choices": [try aerialChoice(assetID: "root-old")]
                ]
            ],
            "Spaces": [
                "wallpaper-space": try spaceRecord(
                    defaultChoices: [aerialChoice(assetID: "target-old")],
                    displayChoices: [aerialChoice(assetID: "target-old")]
                ),
                "other-space": try spaceRecord(
                    defaultChoices: [aerialChoice(assetID: "other-old")],
                    displayChoices: [aerialChoice(assetID: "other-old")]
                )
            ]
        ]
        let indexURL = directory.appendingPathComponent("Index.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try data.write(to: indexURL)

        let reloader = RecordingReloader()
        let store = WallpaperStore(
            indexURL: indexURL,
            reloader: reloader,
            spaceIDResolver: DictionaryWallpaperSpaceIDResolver(
                values: ["4": "wallpaper-space"]
            )
        )
        let target = WallpaperSpaceTarget(spaceID: "4", displayID: "display-1")

        XCTAssertEqual(
            try store.currentAerialIDs(for: [target]),
            ["4": "target-old"]
        )

        try store.setAerialWallpapers(["4": "target-new"], for: [target])

        let updatedRoot = try readStore(at: indexURL)
        let spaces = try XCTUnwrap(updatedRoot["Spaces"] as? [String: Any])
        let targetSpace = try XCTUnwrap(spaces["wallpaper-space"] as? [String: Any])
        let otherSpace = try XCTUnwrap(spaces["other-space"] as? [String: Any])
        let targetDefault = try XCTUnwrap(targetSpace["Default"])
        let targetDisplay = try XCTUnwrap(
            (targetSpace["Displays"] as? [String: Any])?["display-1"]
        )
        let rootDisplay = try XCTUnwrap(
            (updatedRoot["Displays"] as? [String: Any])?["display-1"]
        )

        XCTAssertEqual(firstAssetID(in: targetDefault), "target-new")
        XCTAssertEqual(firstAssetID(in: targetDisplay), "target-new")
        XCTAssertEqual(firstAssetID(in: otherSpace), "other-old")
        XCTAssertEqual(firstAssetID(in: rootDisplay), "root-old")
        XCTAssertEqual(reloader.reloadCount, 1)
    }

    private var imageChoice: [String: Any] {
        [
            "Provider": "com.apple.wallpaper.choice.image",
            "Configuration": Data("unchanged".utf8)
        ]
    }

    private func aerialChoice(assetID: String) throws -> [String: Any] {
        [
            "Provider": "com.apple.wallpaper.choice.aerials",
            "Configuration": try configurationData(assetID: assetID)
        ]
    }

    private func makeStore(
        choices: [[String: Any]]
    ) throws -> (store: WallpaperStore, directory: URL, reloader: RecordingReloader) {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("WallPainterTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let root: [String: Any] = [
            "Spaces": [
                "space-1": [
                    "Choices": choices,
                    "LastSet": Date(timeIntervalSince1970: 0)
                ]
            ]
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        let indexURL = directory.appendingPathComponent("Index.plist")
        try data.write(to: indexURL)

        let reloader = RecordingReloader()
        return (
            WallpaperStore(indexURL: indexURL, reloader: reloader),
            directory,
            reloader
        )
    }

    private func readStore(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try XCTUnwrap(propertyList as? [String: Any])
    }

    private func configurationData(assetID: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )
    }

    private func assetID(from value: Any?) -> String? {
        guard let data = value as? Data,
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let configuration = propertyList as? [String: Any]
        else {
            return nil
        }
        return configuration["assetID"] as? String
    }

    private func spaceRecord(
        defaultChoices: [[String: Any]],
        displayChoices: [[String: Any]]
    ) throws -> [String: Any] {
        [
            "Default": [
                "Linked": [
                    "Content": ["Choices": defaultChoices],
                    "LastSet": Date(timeIntervalSince1970: 0)
                ]
            ],
            "Displays": [
                "display-1": [
                    "Linked": [
                        "Content": ["Choices": displayChoices],
                        "LastSet": Date(timeIntervalSince1970: 0)
                    ]
                ]
            ]
        ]
    }

    private func firstAssetID(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if dictionary["Provider"] as? String == "com.apple.wallpaper.choice.aerials" {
                return assetID(from: dictionary["Configuration"])
            }
            return dictionary.values.lazy.compactMap { self.firstAssetID(in: $0) }.first
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap { self.firstAssetID(in: $0) }.first
        }
        return nil
    }
}

@MainActor
private final class RecordingReloader: WallpaperAgentReloading {
    private(set) var reloadCount = 0

    func reload() throws {
        reloadCount += 1
    }
}

private struct DictionaryWallpaperSpaceIDResolver: WallpaperSpaceIDResolving {
    let values: [String: String]

    func wallpaperStoreSpaceID(for managedSpaceID: String) -> String? {
        values[managedSpaceID]
    }
}
