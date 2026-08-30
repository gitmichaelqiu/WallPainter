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

@MainActor
@Observable
final class WallpaperModel {
    private static let selectedWallpaperKey = "WallPainter.selectedWallpaperID"

    var items: [WallpaperItem] = []
    var selectedWallpaperID: String? {
        didSet {
            if let selectedWallpaperID {
                UserDefaults.standard.set(selectedWallpaperID, forKey: Self.selectedWallpaperKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedWallpaperKey)
            }
        }
    }
    private(set) var currentWallpaperID: String?
    var isLoading = false
    var isSwitching = false
    var operationStatus: WallpaperOperationStatus?

    @ObservationIgnored private let catalog: SystemWallpaperCatalog
    @ObservationIgnored private let store: WallpaperStore

    init(
        catalog: SystemWallpaperCatalog? = nil,
        store: WallpaperStore? = nil
    ) {
        self.catalog = catalog ?? SystemWallpaperCatalog()
        self.store = store ?? WallpaperStore()
        self.selectedWallpaperID = UserDefaults.standard.string(forKey: Self.selectedWallpaperKey)
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
    }

    func switchSelectedWallpaper() {
        guard !isSwitching, let selectedWallpaper else { return }

        isSwitching = true
        operationStatus = nil

        do {
            try store.setAerialWallpaper(assetID: selectedWallpaper.id)
            currentWallpaperID = selectedWallpaper.id
            operationStatus = .success("\(selectedWallpaper.name) is now active on your desktop.")
        } catch {
            operationStatus = .failure(error.localizedDescription)
        }

        isSwitching = false
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
}
