import Foundation
import XCTest

@testable import WallPainter

@MainActor
final class WallpaperAssetProtectionTests: XCTestCase {
    func testRetainsOnlyReferencedWallpapers() throws {
        let directories = try makeDirectories()
        let referenced = makeWallpaper(id: "referenced", directories: directories)
        let unreferenced = makeWallpaper(id: "unreferenced", directories: directories)
        try writeData("referenced", to: referenced.videoURL)
        try writeData("unreferenced", to: unreferenced.videoURL)

        let protector = makeProtector(directories: directories)
        let status = protector.retain(
            items: [referenced, unreferenced],
            for: [referenced.id]
        )

        XCTAssertEqual(status.protectedIDs, Set([referenced.id]))
        XCTAssertEqual(status.missingIDs, Set<String>())
        XCTAssertTrue(fileManager.fileExists(atPath: backupVideoURL(
            for: referenced,
            directories: directories
        ).path))
        XCTAssertFalse(fileManager.fileExists(atPath: backupVideoURL(
            for: unreferenced,
            directories: directories
        ).path))
    }

    func testRestoresMissingWallpaperAndThumbnailFromBackup() throws {
        let directories = try makeDirectories()
        let wallpaper = makeWallpaper(
            id: "restore-me",
            directories: directories,
            hasThumbnail: true
        )
        try writeData("video-data", to: wallpaper.videoURL)
        try writeData("thumbnail-data", to: try XCTUnwrap(wallpaper.thumbnailURL))

        let protector = makeProtector(directories: directories)
        _ = protector.retain(items: [wallpaper], for: [wallpaper.id])
        try fileManager.removeItem(at: wallpaper.videoURL)
        try fileManager.removeItem(at: try XCTUnwrap(wallpaper.thumbnailURL))

        let restoredIDs = protector.restore(protectedIDs: [wallpaper.id])

        XCTAssertTrue(restoredIDs.contains(wallpaper.id))
        XCTAssertEqual(try Data(contentsOf: wallpaper.videoURL), Data("video-data".utf8))
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(wallpaper.thumbnailURL)),
            Data("thumbnail-data".utf8)
        )
    }

    func testRestoreDoesNotOverwriteAnExistingAppleCacheFile() throws {
        let directories = try makeDirectories()
        let wallpaper = makeWallpaper(id: "keep-existing", directories: directories)
        try writeData("apple-cache", to: wallpaper.videoURL)
        try writeData(
            "wallpainter-backup",
            to: backupVideoURL(for: wallpaper, directories: directories)
        )

        let protector = makeProtector(directories: directories)
        let restoredIDs = protector.restore(protectedIDs: [wallpaper.id])

        XCTAssertTrue(restoredIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: wallpaper.videoURL), Data("apple-cache".utf8))
    }

    func testRemoveBackupsDeletesOnlyWallPainterAssets() throws {
        let directories = try makeDirectories()
        let wallpaper = makeWallpaper(id: "remove-me", directories: directories)
        try writeData(
            "backup-data",
            to: backupVideoURL(for: wallpaper, directories: directories)
        )
        try writeData("apple-cache", to: wallpaper.videoURL)

        let protector = makeProtector(directories: directories)
        try protector.removeBackups()

        XCTAssertFalse(fileManager.fileExists(atPath: backupVideoURL(
            for: wallpaper,
            directories: directories
        ).path))
        XCTAssertTrue(fileManager.fileExists(atPath: wallpaper.videoURL.path))
    }

    func testRemoveBackupsVerifiesTheBackupDirectoryIsGone() throws {
        let directories = try makeDirectories()
        let operations = TestAssetFileOperations(mode: .copy, preserveBackupDirectory: true)
        let protector = makeProtector(
            directories: directories,
            fileOperations: operations
        )

        XCTAssertThrowsError(try protector.removeBackups())
        XCTAssertTrue(fileManager.fileExists(atPath: directories.backupDirectory.path))
    }

    func testFailedRestoreLeavesNoPartialAsset() throws {
        let directories = try makeDirectories()
        let wallpaper = makeWallpaper(id: "atomic-failure", directories: directories)
        try writeData(
            "backup-data",
            to: backupVideoURL(for: wallpaper, directories: directories)
        )
        let operations = TestAssetFileOperations(mode: .failure)
        let protector = makeProtector(
            directories: directories,
            fileOperations: operations
        )

        XCTAssertTrue(protector.restore(protectedIDs: [wallpaper.id]).isEmpty)
        XCTAssertEqual(
            protector.status(for: [wallpaper.id]).missingIDs,
            Set([wallpaper.id])
        )
        XCTAssertFalse(fileManager.fileExists(atPath: wallpaper.videoURL.path))
        let systemVideoDirectory = wallpaper.videoURL.deletingLastPathComponent()
        let remainingFiles = try fileManager.contentsOfDirectory(
            at: systemVideoDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remainingFiles.isEmpty)
        XCTAssertEqual(operations.callCount, 1)
    }

    func testRetainUsesInjectedCloneAndCopyOperations() throws {
        for mode in [TestAssetFileOperations.Mode.clone, .copy] {
            let directories = try makeDirectories()
            let wallpaper = makeWallpaper(id: "copy-(mode)", directories: directories)
            try writeData("asset-data", to: wallpaper.videoURL)
            let operations = TestAssetFileOperations(mode: mode)
            let protector = makeProtector(
                directories: directories,
                fileOperations: operations
            )

            let status = protector.retain(items: [wallpaper], for: [wallpaper.id])

            XCTAssertTrue(status.isHealthy)
            XCTAssertEqual(operations.callCount, 1)
            XCTAssertTrue(fileManager.fileExists(atPath: backupVideoURL(
                for: wallpaper,
                directories: directories
            ).path))
        }
    }

    func testCatalogDiscoversAerialAfterRestore() throws {
        let directories = try makeDirectories()
        let wallpaper = makeWallpaper(id: "catalog-restore", directories: directories)
        try writeData("asset-data", to: wallpaper.videoURL)
        try writeManifest(for: wallpaper.id, in: directories.systemAerialDirectory)

        let protector = makeProtector(directories: directories)
        _ = protector.retain(items: [wallpaper], for: [wallpaper.id])
        try fileManager.removeItem(at: wallpaper.videoURL)

        _ = protector.restore(protectedIDs: [wallpaper.id])
        let catalog = SystemWallpaperCatalog(
            fileManager: fileManager,
            applicationSupportDirectory: directories.root,
            nameLocalizer: TestWallpaperNameLocalizer()
        )

        XCTAssertEqual(try catalog.installedAerials().map(\.id), [wallpaper.id])
    }

    func testManualSelectionIsRetainedByWallpaperModel() throws {
        let directories = try makeDirectories()
        let wallpaper = makeWallpaper(id: "manual-selection", directories: directories)
        try writeData("asset-data", to: wallpaper.videoURL)
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        preferences.selectedWallpaperID = wallpaper.id
        let model = WallpaperModel(
            catalog: AssetProtectionTestCatalog(items: [wallpaper]),
            store: AssetProtectionTestStore(),
            preferences: preferences,
            assetProtector: makeProtector(directories: directories)
        )

        model.refresh()

        XCTAssertEqual(preferences.protectedWallpaperIDs, Set([wallpaper.id]))
        XCTAssertEqual(model.assetProtectionStatus.missingIDs, Set<String>())
        XCTAssertTrue(fileManager.fileExists(atPath: backupVideoURL(
            for: wallpaper,
            directories: directories
        ).path))
    }

    func testDisablingProtectionRemovesBackupsCreatedByWallpaperModel() throws {
        let directories = try makeDirectories()
        let wallpaper = makeWallpaper(id: "toggle-protection", directories: directories)
        try writeData("asset-data", to: wallpaper.videoURL)
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        preferences.selectedWallpaperID = wallpaper.id
        let model = WallpaperModel(
            catalog: AssetProtectionTestCatalog(items: [wallpaper]),
            store: AssetProtectionTestStore(),
            preferences: preferences,
            assetProtector: makeProtector(directories: directories)
        )

        model.refresh()
        XCTAssertTrue(fileManager.fileExists(atPath: backupVideoURL(
            for: wallpaper,
            directories: directories
        ).path))

        model.setWallpaperProtectionEnabled(false)

        XCTAssertFalse(fileManager.fileExists(atPath: backupVideoURL(
            for: wallpaper,
            directories: directories
        ).path))
        XCTAssertTrue(model.assetProtectionStatus.protectedIDs.isEmpty)
    }

    func testFailedProtectionDisableKeepsProtectionOnUntilBackupRemovalSucceeds() throws {
        let directories = try makeDirectories()
        let wallpaper = makeWallpaper(id: "retry-protection-disable", directories: directories)
        try writeData("asset-data", to: wallpaper.videoURL)
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        preferences.selectedWallpaperID = wallpaper.id
        let operations = TestAssetFileOperations(mode: .copy, failRemoval: true)
        let model = WallpaperModel(
            catalog: AssetProtectionTestCatalog(items: [wallpaper]),
            store: AssetProtectionTestStore(),
            preferences: preferences,
            assetProtector: makeProtector(
                directories: directories,
                fileOperations: operations
            )
        )
        let backupURL = backupVideoURL(for: wallpaper, directories: directories)

        model.refresh()
        model.setWallpaperProtectionEnabled(false)

        XCTAssertTrue(preferences.wallpaperProtectionEnabled)
        XCTAssertTrue(fileManager.fileExists(atPath: backupURL.path))
        XCTAssertNotNil(model.protectionBackupRemovalError)

        operations.failRemoval = false
        model.retryWallpaperProtectionCleanup()

        XCTAssertFalse(preferences.wallpaperProtectionEnabled)
        XCTAssertFalse(fileManager.fileExists(atPath: directories.backupDirectory.path))
        XCTAssertNil(model.protectionBackupRemovalError)
    }

    func testAutomationRestoresEvictedAppearanceAssetBeforeApplying() throws {
        let directories = try makeDirectories()
        let light = makeWallpaper(id: "light", directories: directories)
        let dark = makeWallpaper(id: "dark", directories: directories)
        try writeData("light-data", to: light.videoURL)
        try writeData("dark-data", to: dark.videoURL)
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        preferences.defaultWallpaperRule = .appearance(
            lightWallpaperID: light.id,
            darkWallpaperID: dark.id
        )
        let store = AssetAutomationTestStore(currentID: "old")
        let monitor = AssetAutomationTestAppearanceMonitor(initialAppearance: .light)
        let model = WallpaperModel(
            catalog: AssetProtectionTestCatalog(items: [light, dark]),
            store: store,
            preferences: preferences,
            assetProtector: makeProtector(directories: directories)
        )
        model.refresh()

        let coordinator = WallpaperAutomationCoordinator(
            model: model,
            preferences: preferences,
            appearanceMonitor: monitor,
            spaceProvider: AssetAutomationTestSpaceProvider()
        )
        defer { coordinator.stop() }
        coordinator.start()
        try fileManager.removeItem(at: dark.videoURL)
        monitor.emit(.dark)

        XCTAssertEqual(store.scopedWrites, [["space-1": light.id], ["space-1": dark.id]])
        XCTAssertEqual(try Data(contentsOf: dark.videoURL), Data("dark-data".utf8))
    }

    func testProtectionStatusReportsMissingUnrecoverableAsset() throws {
        let directories = try makeDirectories()
        let protector = makeProtector(directories: directories)

        let status = protector.status(for: ["not-present"])

        XCTAssertEqual(status.protectedIDs, Set(["not-present"]))
        XCTAssertEqual(status.missingIDs, Set(["not-present"]))
        XCTAssertFalse(status.isHealthy)
    }

    private let fileManager = FileManager.default

    private func makeDirectories() throws -> TestDirectories {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("WallPainterAssetProtection-\(UUID().uuidString)", isDirectory: true)
        let systemAerialDirectory = root
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("aerials", isDirectory: true)
        let backupDirectory = root
            .appendingPathComponent("WallPainter/AerialBackups", isDirectory: true)
        try fileManager.createDirectory(
            at: systemAerialDirectory.appendingPathComponent("videos", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: systemAerialDirectory.appendingPathComponent("thumbnails", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: backupDirectory.appendingPathComponent("videos", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: backupDirectory.appendingPathComponent("thumbnails", isDirectory: true),
            withIntermediateDirectories: true
        )
        return TestDirectories(
            root: root,
            systemAerialDirectory: systemAerialDirectory,
            backupDirectory: backupDirectory
        )
    }

    private func makeProtector(
        directories: TestDirectories,
        fileOperations: (any WallpaperAssetFileOperations)? = nil
    ) -> SystemWallpaperAssetProtector {
        SystemWallpaperAssetProtector(
            fileManager: fileManager,
            systemAerialDirectory: directories.systemAerialDirectory,
            backupDirectory: directories.backupDirectory,
            fileOperations: fileOperations
        )
    }

    private func makeWallpaper(
        id: String,
        directories: TestDirectories,
        hasThumbnail: Bool = false
    ) -> WallpaperItem {
        let videoURL = directories.systemAerialDirectory
            .appendingPathComponent("videos", isDirectory: true)
            .appendingPathComponent("\(id).mov")
        let thumbnailURL = hasThumbnail
            ? directories.systemAerialDirectory
                .appendingPathComponent("thumbnails", isDirectory: true)
                .appendingPathComponent("\(id).png")
            : nil
        return WallpaperItem(
            id: id,
            name: id,
            thumbnailURL: thumbnailURL,
            videoURL: videoURL,
            preferredOrder: 0
        )
    }

    private func backupVideoURL(
        for wallpaper: WallpaperItem,
        directories: TestDirectories
    ) -> URL {
        directories.backupDirectory
            .appendingPathComponent("videos", isDirectory: true)
            .appendingPathComponent("\(wallpaper.id).mov")
    }

    private func writeData(_ string: String, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(string.utf8).write(to: url)
    }

    private func writeManifest(for id: String, in directory: URL) throws {
        let manifest: [String: Any] = [
            "assets": [[
                "id": id,
                "accessibilityLabel": id,
                "preferredOrder": 0,
                "shotID": id
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("manifest", isDirectory: true),
            withIntermediateDirectories: true
        )
        try data.write(
            to: directory
                .appendingPathComponent("manifest", isDirectory: true)
                .appendingPathComponent("entries.json")
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WallPainterAssetProtectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct TestDirectories {
    let root: URL
    let systemAerialDirectory: URL
    let backupDirectory: URL
}

private final class TestAssetFileOperations: WallpaperAssetFileOperations {
    enum Mode: CustomStringConvertible, Equatable {
        case clone
        case copy
        case failure

        var description: String {
            switch self {
            case .clone: return "clone"
            case .copy: return "copy"
            case .failure: return "failure"
            }
        }
    }

    let mode: Mode
    private let fileManager = FileManager.default
    var failRemoval: Bool
    private let preserveBackupDirectory: Bool
    private(set) var callCount = 0

    init(
        mode: Mode,
        failRemoval: Bool = false,
        preserveBackupDirectory: Bool = false
    ) {
        self.mode = mode
        self.failRemoval = failRemoval
        self.preserveBackupDirectory = preserveBackupDirectory
    }

    func cloneOrCopyItem(at sourceURL: URL, to destinationURL: URL) throws {
        callCount += 1
        if mode == .failure {
            throw TestAssetFileOperationError.failed
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        if failRemoval {
            throw TestAssetFileOperationError.failed
        }
        guard !preserveBackupDirectory else { return }
        try fileManager.removeItem(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
}

private enum TestAssetFileOperationError: Error {
    case failed
}

private struct TestWallpaperNameLocalizer: WallpaperNameLocalizing {
    func localizedString(forKey key: String) -> String? {
        nil
    }
}

@MainActor
private struct AssetProtectionTestCatalog: WallpaperCatalogProviding {
    let items: [WallpaperItem]

    func installedAerials() throws -> [WallpaperItem] {
        items
    }
}

@MainActor
private final class AssetProtectionTestStore: WallpaperStoring {
    func currentAerialID() throws -> String? { nil }

    func setAerialWallpaper(assetID: String) throws {}
}

@MainActor
private final class AssetAutomationTestStore: WallpaperStoring {
    var currentID: String?
    private(set) var scopedWrites: [[String: String]] = []

    init(currentID: String?) {
        self.currentID = currentID
    }

    func currentAerialID() throws -> String? {
        currentID
    }

    func setAerialWallpaper(assetID: String) throws {
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
        currentID = wallpaperIDsBySpaceID.values.first
    }
}

@MainActor
private final class AssetAutomationTestSpaceProvider: SpaceAPIProviding {
    let snapshot: SpaceSnapshot? = SpaceSnapshot(
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
    let isAvailable = true

    func start() {}
    func stop() {}
    func refresh() {}
}

@MainActor
private final class AssetAutomationTestAppearanceMonitor: AppearanceMonitoring {
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
