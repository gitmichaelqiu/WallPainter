import Foundation

enum WallpaperRuleMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixed
    case appearance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixed:
            return "Fixed wallpaper"
        case .appearance:
            return "Follow system appearance"
        }
    }
}

struct WallpaperRule: Codable, Equatable, Sendable {
    var mode: WallpaperRuleMode
    var fixedWallpaperID: String?
    var lightWallpaperID: String?
    var darkWallpaperID: String?

    static let emptyAppearance = WallpaperRule(
        mode: .appearance,
        fixedWallpaperID: nil,
        lightWallpaperID: nil,
        darkWallpaperID: nil
    )

    static func fixed(_ wallpaperID: String? = nil) -> WallpaperRule {
        WallpaperRule(
            mode: .fixed,
            fixedWallpaperID: wallpaperID,
            lightWallpaperID: nil,
            darkWallpaperID: nil
        )
    }

    static func appearance(
        lightWallpaperID: String? = nil,
        darkWallpaperID: String? = nil
    ) -> WallpaperRule {
        WallpaperRule(
            mode: .appearance,
            fixedWallpaperID: nil,
            lightWallpaperID: lightWallpaperID,
            darkWallpaperID: darkWallpaperID
        )
    }

    func isValid(installedWallpaperIDs: Set<String>) -> Bool {
        switch mode {
        case .fixed:
            guard let fixedWallpaperID else { return false }
            return installedWallpaperIDs.contains(fixedWallpaperID)
        case .appearance:
            guard let lightWallpaperID, let darkWallpaperID else { return false }
            return installedWallpaperIDs.contains(lightWallpaperID)
                && installedWallpaperIDs.contains(darkWallpaperID)
        }
    }

    func resolvedWallpaperID(for appearance: WallpaperAppearance) -> String? {
        switch mode {
        case .fixed:
            return fixedWallpaperID
        case .appearance:
            switch appearance {
            case .light:
                return lightWallpaperID
            case .dark:
                return darkWallpaperID
            }
        }
    }
}

struct WallpaperSpaceTarget: Codable, Equatable, Hashable, Sendable {
    let spaceID: String
    let displayID: String

    init(spaceID: String, displayID: String) {
        self.spaceID = spaceID
        self.displayID = displayID
    }
}

enum WallpaperActiveState: Equatable, Sendable {
    case unavailable
    case empty
    case uniform(String)
    case mixed
}
