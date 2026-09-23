import Darwin
import Foundation

struct WallpaperAssetProtectionStatus: Equatable, Sendable {
    let protectedIDs: Set<String>
    let availableIDs: Set<String>

    var missingIDs: Set<String> {
        protectedIDs.subtracting(availableIDs)
    }

    var isHealthy: Bool {
        missingIDs.isEmpty
    }
}

protocol WallpaperAssetProtecting {
    func restore(protectedIDs: Set<String>) -> Set<String>
    func retain(
        items: [WallpaperItem],
        for protectedIDs: Set<String>
    ) -> WallpaperAssetProtectionStatus
    func status(for protectedIDs: Set<String>) -> WallpaperAssetProtectionStatus
    func removeBackups() throws
}

protocol WallpaperAssetFileOperations {
    func cloneOrCopyItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
    func fileExists(at url: URL) -> Bool
}

struct DefaultWallpaperAssetFileOperations: WallpaperAssetFileOperations {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func cloneOrCopyItem(at sourceURL: URL, to destinationURL: URL) throws {
        if clonefile(sourceURL.path, destinationURL.path, 0) == 0 {
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
}

struct NoopWallpaperAssetProtector: WallpaperAssetProtecting {
    func restore(protectedIDs: Set<String>) -> Set<String> {
        []
    }

    func retain(
        items: [WallpaperItem],
        for protectedIDs: Set<String>
    ) -> WallpaperAssetProtectionStatus {
        status(for: protectedIDs)
    }

    func status(for protectedIDs: Set<String>) -> WallpaperAssetProtectionStatus {
        WallpaperAssetProtectionStatus(
            protectedIDs: protectedIDs,
            availableIDs: protectedIDs
        )
    }

    func removeBackups() throws { }
}

struct SystemWallpaperAssetProtector: WallpaperAssetProtecting {
    private enum AssetProtectionError: LocalizedError {
        case invalidCopiedAsset
        case backupsStillExist

        var errorDescription: String? {
            switch self {
            case .invalidCopiedAsset:
                return String(localized: "The copied wallpaper asset failed verification.")
            case .backupsStillExist:
                return String(localized: "WallPainter's wallpaper backups still exist after removal.")
            }
        }
    }

    private static let thumbnailExtensions = ["png", "jpg", "jpeg", "heic"]

    private let fileManager: FileManager
    private let systemAerialDirectory: URL
    private let backupDirectory: URL
    private let fileOperations: any WallpaperAssetFileOperations

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        systemAerialDirectory: URL? = nil,
        backupDirectory: URL? = nil,
        fileOperations: (any WallpaperAssetFileOperations)? = nil
    ) {
        self.fileManager = fileManager

        let supportDirectory = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        self.systemAerialDirectory = systemAerialDirectory
            ?? supportDirectory
                .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
                .appendingPathComponent("aerials", isDirectory: true)
        self.backupDirectory = backupDirectory
            ?? supportDirectory
                .appendingPathComponent("WallPainter", isDirectory: true)
                .appendingPathComponent("AerialBackups", isDirectory: true)
        self.fileOperations = fileOperations
            ?? DefaultWallpaperAssetFileOperations(fileManager: fileManager)
    }

    func restore(protectedIDs: Set<String>) -> Set<String> {
        var restoredIDs = Set<String>()

        for wallpaperID in protectedIDs {
            guard let paths = paths(for: wallpaperID) else { continue }

            if !isUsableFile(at: paths.systemVideoURL),
               isUsableFile(at: paths.backupVideoURL),
               installAtomically(
                sourceURL: paths.backupVideoURL,
                destinationURL: paths.systemVideoURL
               ) {
                restoredIDs.insert(wallpaperID)
            }

            if let backupThumbnail = firstUsableThumbnailURL(
                in: paths.backupThumbnailDirectory,
                wallpaperID: wallpaperID
            ),
            let systemThumbnail = thumbnailURL(
                in: paths.systemThumbnailDirectory,
                wallpaperID: wallpaperID,
                fileExtension: backupThumbnail.pathExtension
            ),
            !isUsableFile(at: systemThumbnail),
            installAtomically(
                sourceURL: backupThumbnail,
                destinationURL: systemThumbnail
            ) {
                restoredIDs.insert(wallpaperID)
            }
        }

        return restoredIDs
    }

    func retain(
        items: [WallpaperItem],
        for protectedIDs: Set<String>
    ) -> WallpaperAssetProtectionStatus {
        for item in items where protectedIDs.contains(item.id) {
            guard let paths = paths(for: item.id) else { continue }

            if isUsableFile(at: item.videoURL),
               !isUsableFile(at: paths.backupVideoURL) {
                _ = installAtomically(
                    sourceURL: item.videoURL,
                    destinationURL: paths.backupVideoURL
                )
            }

            if let sourceThumbnailURL = item.thumbnailURL,
               isUsableFile(at: sourceThumbnailURL),
               let backupThumbnailURL = thumbnailURL(
                in: paths.backupThumbnailDirectory,
                wallpaperID: item.id,
                fileExtension: sourceThumbnailURL.pathExtension
               ),
               !isUsableFile(at: backupThumbnailURL) {
                _ = installAtomically(
                    sourceURL: sourceThumbnailURL,
                    destinationURL: backupThumbnailURL
                )
            }
        }

        return status(for: protectedIDs)
    }

    func status(for protectedIDs: Set<String>) -> WallpaperAssetProtectionStatus {
        let availableIDs = Set(
            protectedIDs.filter { wallpaperID in
                guard let paths = paths(for: wallpaperID) else { return false }
                return isUsableFile(at: paths.systemVideoURL)
            }
        )

        return WallpaperAssetProtectionStatus(
            protectedIDs: protectedIDs,
            availableIDs: availableIDs
        )
    }

    func removeBackups() throws {
        guard fileOperations.fileExists(at: backupDirectory) else { return }
        try fileOperations.removeItem(at: backupDirectory)
        guard !fileOperations.fileExists(at: backupDirectory) else {
            throw AssetProtectionError.backupsStillExist
        }
    }

    private struct AssetPaths {
        let systemVideoURL: URL
        let backupVideoURL: URL
        let systemThumbnailDirectory: URL
        let backupThumbnailDirectory: URL
    }

    private func paths(for wallpaperID: String) -> AssetPaths? {
        guard isSafeComponent(wallpaperID) else { return nil }

        let systemVideoDirectory = systemAerialDirectory
            .appendingPathComponent("videos", isDirectory: true)
        let backupVideoDirectory = backupDirectory
            .appendingPathComponent("videos", isDirectory: true)
        let systemThumbnailDirectory = systemAerialDirectory
            .appendingPathComponent("thumbnails", isDirectory: true)
        let backupThumbnailDirectory = backupDirectory
            .appendingPathComponent("thumbnails", isDirectory: true)

        return AssetPaths(
            systemVideoURL: systemVideoDirectory
                .appendingPathComponent("\(wallpaperID).mov"),
            backupVideoURL: backupVideoDirectory
                .appendingPathComponent("\(wallpaperID).mov"),
            systemThumbnailDirectory: systemThumbnailDirectory,
            backupThumbnailDirectory: backupThumbnailDirectory
        )
    }

    private func firstUsableThumbnailURL(
        in directory: URL,
        wallpaperID: String
    ) -> URL? {
        for fileExtension in Self.thumbnailExtensions {
            guard let url = thumbnailURL(
                in: directory,
                wallpaperID: wallpaperID,
                fileExtension: fileExtension
            ),
            isUsableFile(at: url)
            else {
                continue
            }
            return url
        }
        return nil
    }

    private func thumbnailURL(
        in directory: URL,
        wallpaperID: String,
        fileExtension: String
    ) -> URL? {
        guard isSafeComponent(wallpaperID),
              isSafeComponent(fileExtension)
        else { return nil }

        return directory.appendingPathComponent(
            "\(wallpaperID).\(fileExtension)",
            isDirectory: false
        )
    }

    private func installAtomically(sourceURL: URL, destinationURL: URL) -> Bool {
        guard isUsableFile(at: sourceURL) else { return false }

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let temporaryURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
                )
            defer { try? fileManager.removeItem(at: temporaryURL) }

            try fileOperations.cloneOrCopyItem(
                at: sourceURL,
                to: temporaryURL
            )
            guard isUsableFile(at: temporaryURL) else {
                throw AssetProtectionError.invalidCopiedAsset
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            guard isUsableFile(at: destinationURL) else {
                throw AssetProtectionError.invalidCopiedAsset
            }
            return true
        } catch {
            return false
        }
    }

    private func isUsableFile(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey
              ]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0
        else {
            return false
        }

        return true
    }

    private func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.contains("\\")
    }
}
