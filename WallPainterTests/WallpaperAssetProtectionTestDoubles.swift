import Foundation

@testable import WallPainter

struct TestDirectories {
    let root: URL
    let systemAerialDirectory: URL
    let backupDirectory: URL
}

final class TestAssetFileOperations: WallpaperAssetFileOperations {
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

struct AssetProtectionTestWallpaperNameLocalizer: WallpaperNameLocalizing {
    func localizedString(forKey key: String) -> String? {
        nil
    }
}

@MainActor
struct AssetProtectionTestCatalog: WallpaperCatalogProviding {
    let items: [WallpaperItem]

    func installedAerials() throws -> [WallpaperItem] {
        items
    }
}

@MainActor
final class AssetProtectionTestStore: WallpaperStoring {
    func currentAerialID() throws -> String? { nil }

    func setAerialWallpaper(assetID: String) throws {}
}

@MainActor
final class AssetAutomationTestStore: WallpaperStoring {
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
final class AssetAutomationTestSpaceProvider: SpaceAPIProviding {
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
final class AssetAutomationTestAppearanceMonitor: AppearanceMonitoring {
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
