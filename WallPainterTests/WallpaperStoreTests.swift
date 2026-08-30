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
}

@MainActor
private final class RecordingReloader: WallpaperAgentReloading {
    private(set) var reloadCount = 0

    func reload() throws {
        reloadCount += 1
    }
}
