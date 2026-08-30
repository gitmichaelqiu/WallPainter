import Foundation

protocol WallpaperCatalogProviding {
    func installedAerials() throws -> [WallpaperItem]
}

protocol WallpaperStoring {
    func currentAerialID() throws -> String?
    func setAerialWallpaper(assetID: String) throws
}
