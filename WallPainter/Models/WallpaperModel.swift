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
    private(set) var currentWallpaperIDsBySpaceID: [String: String] = [:]
    private(set) var currentWallpaperState: WallpaperActiveState = .empty
    private(set) var activeSpaceTargets: [WallpaperSpaceTarget] = []
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
        switch currentWallpaperState {
        case .mixed:
            return "Multiple wallpapers"
        case .unavailable:
            return "Not detected"
        case .empty:
            if let currentWallpaperID {
                return name(for: currentWallpaperID)
            }
            return "Not detected"
        case .uniform(let wallpaperID):
            return name(for: wallpaperID)
        }
    }

    var currentWallpaperSummary: String {
        switch currentWallpaperState {
        case .mixed:
            return "Multiple wallpapers"
        case .unavailable:
            return "Unavailable"
        case .empty:
            return "Not detected"
        case .uniform:
            return currentWallpaperName
        }
    }

    func refresh() {
        isLoading = true
        operationStatus = nil

        do {
            items = try catalog.installedAerials()
            if activeSpaceTargets.isEmpty {
                currentWallpaperID = try? store.currentAerialID()
                currentWallpaperIDsBySpaceID = [:]
                updateCurrentWallpaperState()
            } else {
                synchronizeCurrentWallpapers(for: activeSpaceTargets)
            }
            normalizeSelection()
        } catch {
            items = []
            currentWallpaperID = nil
            currentWallpaperIDsBySpaceID = [:]
            currentWallpaperState = .empty
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

    func setActiveSpaceTargets(_ targets: [WallpaperSpaceTarget]) {
        let normalizedTargets = uniqueTargets(targets)
        guard normalizedTargets != activeSpaceTargets else { return }
        activeSpaceTargets = normalizedTargets
        synchronizeCurrentWallpapers(for: normalizedTargets)
    }

    func synchronizeCurrentWallpaper() {
        if activeSpaceTargets.isEmpty {
            currentWallpaperID = try? store.currentAerialID()
            currentWallpaperIDsBySpaceID = [:]
            updateCurrentWallpaperState()
            postChange()
        } else {
            synchronizeCurrentWallpapers(for: activeSpaceTargets)
        }
    }

    func synchronizeCurrentWallpapers(for targets: [WallpaperSpaceTarget]) {
        let normalizedTargets = uniqueTargets(targets)
        activeSpaceTargets = normalizedTargets

        readCurrentWallpapers(for: normalizedTargets)
        updateCurrentWallpaperState()
        postChange()
    }

    /// Refreshes the cached values for the supplied spaces without changing which
    /// spaces are considered active in the settings and status-bar surfaces.
    func synchronizeWallpaperIDs(for targets: [WallpaperSpaceTarget]) {
        let normalizedTargets = uniqueTargets(targets)
        readCurrentWallpapers(for: normalizedTargets)
        if normalizedTargets == activeSpaceTargets {
            updateCurrentWallpaperState()
        }
        postChange()
    }

    private func readCurrentWallpapers(for targets: [WallpaperSpaceTarget]) {
        let normalizedTargets = uniqueTargets(targets)

        do {
            let IDs = try store.currentAerialIDs(for: normalizedTargets)
            for target in normalizedTargets {
                currentWallpaperIDsBySpaceID.removeValue(forKey: target.spaceID)
            }
            currentWallpaperIDsBySpaceID.merge(IDs) { _, new in new }
            updateCurrentWallpaperState()
        } catch {
            currentWallpaperState = .unavailable
        }
    }

    func wallpaperIDs(for targets: [WallpaperSpaceTarget]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: uniqueTargets(targets).compactMap { target in
            guard let wallpaperID = currentWallpaperIDsBySpaceID[target.spaceID] else {
                return nil
            }
            return (target.spaceID, wallpaperID)
        })
    }

    func wallpaperState(for targets: [WallpaperSpaceTarget]) -> WallpaperActiveState {
        let IDs = uniqueTargets(targets).compactMap { currentWallpaperIDsBySpaceID[$0.spaceID] }
        guard !IDs.isEmpty else { return .empty }
        let uniqueIDs = Set(IDs)
        guard uniqueIDs.count == 1, let wallpaperID = uniqueIDs.first else { return .mixed }
        return .uniform(wallpaperID)
    }

    @discardableResult
    func applyWallpaper(id: String) -> Bool {
        applyWallpaperEverywhere(id: id)
    }

    @discardableResult
    func applyWallpaperEverywhere(id: String) -> Bool {
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

        if activeSpaceTargets.isEmpty, currentWallpaperID == wallpaper.id {
            selectedWallpaperID = wallpaper.id
            operationStatus = .success("\(wallpaper.name) is already active on your desktop.")
            return true
        }

        do {
            try store.setAerialWallpaper(assetID: wallpaper.id)
            currentWallpaperIDsBySpaceID = activeSpaceTargets.reduce(into: [:]) { result, target in
                result[target.spaceID] = wallpaper.id
            }
            currentWallpaperID = wallpaper.id
            currentWallpaperState = .uniform(wallpaper.id)
            selectedWallpaperID = wallpaper.id
            operationStatus = .success("\(wallpaper.name) is now active everywhere.")
            return true
        } catch {
            operationStatus = .failure(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func applyWallpaper(id: String, to targets: [WallpaperSpaceTarget]) -> Bool {
        let normalizedTargets = uniqueTargets(targets)
        guard !normalizedTargets.isEmpty else {
            operationStatus = .failure("No active regular spaces are available.")
            postChange()
            return false
        }
        let IDs = Dictionary(uniqueKeysWithValues: normalizedTargets.map { ($0.spaceID, id) })
        return applyWallpapers(IDs, to: normalizedTargets)
    }

    @discardableResult
    func applyWallpapers(
        _ wallpaperIDsBySpaceID: [String: String],
        to targets: [WallpaperSpaceTarget]
    ) -> Bool {
        let normalizedTargets = uniqueTargets(targets)
        guard !isSwitching else { return false }
        guard !normalizedTargets.isEmpty else {
            operationStatus = .failure("No regular spaces are available.")
            postChange()
            return false
        }

        for target in normalizedTargets {
            guard let wallpaperID = wallpaperIDsBySpaceID[target.spaceID],
                  items.contains(where: { $0.id == wallpaperID })
            else {
                operationStatus = .failure("The selected wallpaper is not installed.")
                postChange()
                return false
            }
        }

        let currentIDs = wallpaperIDs(for: normalizedTargets)
        if normalizedTargets.allSatisfy({ currentIDs[$0.spaceID] == wallpaperIDsBySpaceID[$0.spaceID] }) {
            if let firstID = normalizedTargets.compactMap({ wallpaperIDsBySpaceID[$0.spaceID] }).first {
                selectedWallpaperID = firstID
            }
            updateCurrentWallpaperState()
            operationStatus = .success("The selected wallpaper is already active.")
            postChange()
            return true
        }

        isSwitching = true
        operationStatus = nil
        defer {
            isSwitching = false
            postChange()
        }

        do {
            try store.setAerialWallpapers(wallpaperIDsBySpaceID, for: normalizedTargets)
            currentWallpaperIDsBySpaceID.merge(wallpaperIDsBySpaceID) { _, new in new }
            updateCurrentWallpaperState()
            if let firstID = normalizedTargets.compactMap({ wallpaperIDsBySpaceID[$0.spaceID] }).first {
                selectedWallpaperID = firstID
                let names = Set(normalizedTargets.compactMap { target in
                    wallpaperIDsBySpaceID[target.spaceID]
                }.compactMap { id in
                    items.first(where: { $0.id == id })?.name
                })
                operationStatus = .success(names.count == 1
                    ? "\(names.first ?? "Wallpaper") is now active on the selected spaces."
                    : "Wallpapers are now active on the selected spaces.")
            }
            return true
        } catch {
            operationStatus = .failure(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func switchSelectedWallpaper() -> Bool {
        guard let selectedWallpaper else { return false }
        return applyWallpaperEverywhere(id: selectedWallpaper.id)
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

    private func name(for wallpaperID: String) -> String {
        if let item = items.first(where: { $0.id == wallpaperID }) {
            return item.name
        }
        return "Apple Aerial \(wallpaperID.prefix(8))"
    }

    private func updateCurrentWallpaperState() {
        if !activeSpaceTargets.isEmpty {
            currentWallpaperState = wallpaperState(for: activeSpaceTargets)
            switch currentWallpaperState {
            case .uniform(let wallpaperID):
                currentWallpaperID = wallpaperID
            case .mixed, .empty, .unavailable:
                currentWallpaperID = nil
            }
            return
        }

        if let currentWallpaperID {
            currentWallpaperState = .uniform(currentWallpaperID)
        } else {
            currentWallpaperState = .empty
        }
    }

    private func uniqueTargets(_ targets: [WallpaperSpaceTarget]) -> [WallpaperSpaceTarget] {
        var seenSpaceIDs = Set<String>()
        return targets.filter { target in
            guard !target.spaceID.isEmpty,
                  seenSpaceIDs.insert(target.spaceID).inserted
            else { return false }
            return true
        }
    }

    private func postChange() {
        NotificationCenter.default.post(
            name: .wallPainterWallpaperModelDidChange,
            object: self
        )
    }
}
