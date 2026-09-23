import Foundation

protocol WallpaperCatalogProviding {
    func installedAerials() throws -> [WallpaperItem]
}

protocol WallpaperStoring {
    func currentAerialID() throws -> String?
    func setAerialWallpaper(assetID: String) throws
    func currentAerialIDs(for targets: [WallpaperSpaceTarget]) throws -> [String: String]
    func setAerialWallpapers(
        _ wallpaperIDsBySpaceID: [String: String],
        for targets: [WallpaperSpaceTarget]
    ) throws
}

protocol WallpaperSpaceIDResolving {
    func wallpaperStoreSpaceID(for managedSpaceID: String) -> String?
}

enum WallpaperScopedStoreError: LocalizedError {
    case unsupportedMixedWrite

    var errorDescription: String? {
        switch self {
        case .unsupportedMixedWrite:
            return "This wallpaper store does not support a mixed space-scoped write."
        }
    }
}

extension WallpaperStoring {
    func currentAerialIDs(for targets: [WallpaperSpaceTarget]) throws -> [String: String] {
        guard let wallpaperID = try currentAerialID() else { return [:] }
        return Dictionary(uniqueKeysWithValues: targets.map { ($0.spaceID, wallpaperID) })
    }

    func setAerialWallpapers(
        _ wallpaperIDsBySpaceID: [String: String],
        for targets: [WallpaperSpaceTarget]
    ) throws {
        let wallpaperIDs = Set(targets.compactMap { wallpaperIDsBySpaceID[$0.spaceID] })
        guard wallpaperIDs.count <= 1,
              let wallpaperID = wallpaperIDs.first
        else {
            throw WallpaperScopedStoreError.unsupportedMixedWrite
        }
        try setAerialWallpaper(assetID: wallpaperID)
    }
}
