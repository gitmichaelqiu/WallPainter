import Foundation
import Observation

enum WallpaperOperationStatus: Equatable {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .success(let message), .failure(let message):
            return message
        }
    }

    var symbolName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

extension Notification.Name {
    static let wallPainterWallpaperModelDidChange = Notification.Name(
        "WallPainter.wallpaperModelDidChange"
    )
    static let wallPainterWallpaperCatalogDidChange = Notification.Name(
        "WallPainter.wallpaperCatalogDidChange"
    )
}

@MainActor
@Observable
final class WallpaperModel {
    var items: [WallpaperItem] = []
    var selectedWallpaperID: String? {
        didSet {
            preferences.selectedWallpaperID = selectedWallpaperID
        }
    }
    private(set) var currentWallpaperID: String?
    var isLoading = false
    var isSwitching = false
    var operationStatus: WallpaperOperationStatus?

    @ObservationIgnored private let catalog: any WallpaperCatalogProviding
    @ObservationIgnored private let store: any WallpaperStoring
    @ObservationIgnored private let preferences: WallPainterPreferences

    init(
        catalog: (any WallpaperCatalogProviding)? = nil,
        store: (any WallpaperStoring)? = nil,
        preferences: WallPainterPreferences? = nil
    ) {
        self.catalog = catalog ?? SystemWallpaperCatalog()
        self.store = store ?? WallpaperStore()
        let preferences = preferences ?? WallPainterPreferences()
        self.preferences = preferences
        selectedWallpaperID = preferences.selectedWallpaperID
    }

    var selectedWallpaper: WallpaperItem? {
        guard let selectedWallpaperID else { return nil }
        return items.first { $0.id == selectedWallpaperID }
    }

    var currentWallpaperName: String {
        if let currentWallpaperID,
           let currentItem = items.first(where: { $0.id == currentWallpaperID }) {
            return currentItem.name
        }
        if let currentWallpaperID {
            return "Apple Aerial \(currentWallpaperID.prefix(8))"
        }
        return "Not detected"
    }

    func refresh() {
        isLoading = true
        operationStatus = nil

        do {
            items = try catalog.installedAerials()
            currentWallpaperID = try? store.currentAerialID()
            normalizeSelection()
        } catch {
            items = []
            currentWallpaperID = nil
            selectedWallpaperID = nil
            operationStatus = .failure(error.localizedDescription)
        }

        isLoading = false
        postChange()
        NotificationCenter.default.post(
            name: .wallPainterWallpaperCatalogDidChange,
            object: self
        )
    }

    func synchronizeCurrentWallpaper() {
        currentWallpaperID = try? store.currentAerialID()
        postChange()
    }

    @discardableResult
    func applyWallpaper(id: String) -> Bool {
        guard !isSwitching else { return false }
        guard let wallpaper = items.first(where: { $0.id == id }) else {
            operationStatus = .failure("The selected wallpaper is not installed.")
            postChange()
            return false
        }

        isSwitching = true
        operationStatus = nil
        defer {
            isSwitching = false
            postChange()
        }

        if currentWallpaperID == wallpaper.id {
            selectedWallpaperID = wallpaper.id
            operationStatus = .success("\(wallpaper.name) is already active on your desktop.")
            return true
        }

        do {
            try store.setAerialWallpaper(assetID: wallpaper.id)
            currentWallpaperID = wallpaper.id
            selectedWallpaperID = wallpaper.id
            operationStatus = .success("\(wallpaper.name) is now active on your desktop.")
            return true
        } catch {
            operationStatus = .failure(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func switchSelectedWallpaper() -> Bool {
        guard let selectedWallpaper else { return false }
        return applyWallpaper(id: selectedWallpaper.id)
    }

    private func normalizeSelection() {
        if let selectedWallpaperID,
           items.contains(where: { $0.id == selectedWallpaperID }) {
            return
        }

        if let currentWallpaperID,
           items.contains(where: { $0.id == currentWallpaperID }) {
            selectedWallpaperID = currentWallpaperID
        } else {
            selectedWallpaperID = items.first?.id
        }
    }

    private func postChange() {
        NotificationCenter.default.post(
            name: .wallPainterWallpaperModelDidChange,
            object: self
        )
    }
}
