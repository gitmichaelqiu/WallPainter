import AppKit
import Foundation
import Observation

enum WallpaperAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case light
    case dark

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    init(effectiveAppearance: NSAppearance) {
        self = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark
            : .light
    }
}

@MainActor
protocol AppearanceMonitoring {
    func start(handler: @escaping (WallpaperAppearance) -> Void)
    func stop()
}

@MainActor
final class SystemAppearanceMonitor: AppearanceMonitoring {
    private var observation: NSKeyValueObservation?
    private var handler: ((WallpaperAppearance) -> Void)?

    func start(handler: @escaping (WallpaperAppearance) -> Void) {
        stop()
        self.handler = handler

        observation = NSApp.observe(
            \.effectiveAppearance,
            options: [.initial, .new]
        ) { [weak self] application, _ in
            let appearance = WallpaperAppearance(
                effectiveAppearance: application.effectiveAppearance
            )
            Task { @MainActor [weak self] in
                self?.handler?(appearance)
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        handler = nil
    }
}

@MainActor
@Observable
final class WallpaperAutomationCoordinator {
    let model: WallpaperModel
    let preferences: WallPainterPreferences

    var currentAppearance: WallpaperAppearance = .light
    private(set) var isRunning = false

    @ObservationIgnored private let appearanceMonitor: any AppearanceMonitoring
    @ObservationIgnored private let spaceProvider: (any SpaceAPIProviding)?
    @ObservationIgnored private var catalogObserver: NSObjectProtocol?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    @ObservationIgnored private var spaceSnapshotObserver: NSObjectProtocol?
    @ObservationIgnored private var spaceAvailabilityObserver: NSObjectProtocol?
    @ObservationIgnored private var appearanceEvaluationWorkItem: DispatchWorkItem?

    init(
        model: WallpaperModel,
        preferences: WallPainterPreferences,
        appearanceMonitor: (any AppearanceMonitoring)? = nil,
        spaceProvider: (any SpaceAPIProviding)? = nil
    ) {
        self.model = model
        self.preferences = preferences
        self.appearanceMonitor = appearanceMonitor ?? SystemAppearanceMonitor()
        self.spaceProvider = spaceProvider
    }

    var isSpaceAPIAvailable: Bool {
        spaceProvider?.isAvailable == true
    }

    var hasValidMappings: Bool {
        preferences.defaultWallpaperRule.isValid(
            installedWallpaperIDs: Set(model.items.map(\.id))
        )
    }

    func targetWallpaperID(for appearance: WallpaperAppearance) -> String? {
        preferences.defaultWallpaperRule.resolvedWallpaperID(for: appearance)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        currentAppearance = WallpaperAppearance(effectiveAppearance: NSApp.effectiveAppearance)

        let notificationCenter = NotificationCenter.default
        catalogObserver = notificationCenter.addObserver(
            forName: .wallPainterWallpaperCatalogDidChange,
            object: model,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.catalogDidChange()
            }
        }
        preferencesObserver = notificationCenter.addObserver(
            forName: .wallPainterPreferencesDidChange,
            object: preferences,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.preferencesDidChange()
            }
        }
        if let spaceProvider {
            let observedSpaceProvider = spaceProvider as AnyObject
            spaceSnapshotObserver = notificationCenter.addObserver(
                forName: .wallPainterSpaceSnapshotDidChange,
                object: observedSpaceProvider,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.spaceStateDidChange()
                }
            }
            spaceAvailabilityObserver = notificationCenter.addObserver(
                forName: .wallPainterSpaceAvailabilityDidChange,
                object: observedSpaceProvider,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.spaceStateDidChange()
                }
            }
        }

        spaceProvider?.start()
        appearanceMonitor.start { [weak self] appearance in
            self?.appearanceDidChange(appearance)
        }
    }

    func stop() {
        guard isRunning else { return }

        appearanceMonitor.stop()
        spaceProvider?.stop()
        appearanceEvaluationWorkItem?.cancel()
        appearanceEvaluationWorkItem = nil

        let notificationCenter = NotificationCenter.default
        if let catalogObserver {
            notificationCenter.removeObserver(catalogObserver)
        }
        if let preferencesObserver {
            notificationCenter.removeObserver(preferencesObserver)
        }
        if let spaceSnapshotObserver {
            notificationCenter.removeObserver(spaceSnapshotObserver)
        }
        if let spaceAvailabilityObserver {
            notificationCenter.removeObserver(spaceAvailabilityObserver)
        }
        self.catalogObserver = nil
        self.preferencesObserver = nil
        self.spaceSnapshotObserver = nil
        self.spaceAvailabilityObserver = nil
        isRunning = false
    }

    func evaluateCurrentAppearance() {
        // Reconcile the private Apple cache before resolving rules. A restored
        // asset is discovered by the catalog here; an unrecoverable asset is
        // removed from the installed set and its saved rule is left intact.
        model.reconcileProtectedAssets()

        guard let spaceProvider,
              spaceProvider.isAvailable,
              let snapshot = spaceProvider.snapshot
        else {
            // Space-aware automation never falls back to a global write. The
            // explicit Apply Everywhere action remains available in General.
            return
        }

        let regularSpaces = snapshot.spaces.filter { !$0.isFullscreen }
        guard !regularSpaces.isEmpty else { return }

        synchronizeActiveSpaces()

        let targets = regularSpaces.map {
            WallpaperSpaceTarget(spaceID: $0.id, displayID: $0.displayID)
        }
        model.synchronizeWallpaperIDs(for: targets)

        var wallpaperIDsBySpaceID: [String: String] = [:]
        var writableTargets: [WallpaperSpaceTarget] = []
        let currentWallpaperIDs = model.wallpaperIDs(for: targets)
        let installedWallpaperIDs = Set(model.items.map(\.id))

        for space in regularSpaces {
            let rule = preferences.spaceRule(for: space.id)
                ?? preferences.defaultWallpaperRule

            // An invalid per-space override remains saved for repair, but does
            // not prevent valid spaces from being automated.
            guard rule.isValid(installedWallpaperIDs: installedWallpaperIDs) else {
                continue
            }
            guard let wallpaperID = rule.resolvedWallpaperID(for: currentAppearance) else {
                continue
            }

            guard currentWallpaperIDs[space.id] != wallpaperID else {
                continue
            }

            wallpaperIDsBySpaceID[space.id] = wallpaperID
            writableTargets.append(
                WallpaperSpaceTarget(spaceID: space.id, displayID: space.displayID)
            )
        }

        guard !writableTargets.isEmpty else { return }
        _ = model.applyWallpapers(wallpaperIDsBySpaceID, to: writableTargets)
    }

    private func synchronizeActiveSpaces() {
        guard let spaceProvider,
              spaceProvider.isAvailable,
              let snapshot = spaceProvider.snapshot
        else { return }

        let regularSpacesByID = Dictionary(
            uniqueKeysWithValues: snapshot.spaces
                .filter { !$0.isFullscreen }
                .map { ($0.id, $0) }
        )
        let targets: [WallpaperSpaceTarget] = snapshot.currentSpaceIDs.compactMap { spaceID in
            guard let space = regularSpacesByID[spaceID] else { return nil }
            return WallpaperSpaceTarget(spaceID: space.id, displayID: space.displayID)
        }
        model.setActiveSpaceTargets(targets)
        if !targets.isEmpty {
            model.synchronizeCurrentWallpapers(for: targets)
        }
    }

    private func appearanceDidChange(_ appearance: WallpaperAppearance) {
        currentAppearance = appearance
        evaluateCurrentAppearance()

        appearanceEvaluationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.evaluateCurrentAppearance()
            }
        }
        appearanceEvaluationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func catalogDidChange() {
        evaluateCurrentAppearance()
    }

    private func preferencesDidChange() {
        evaluateCurrentAppearance()
    }

    private func spaceStateDidChange() {
        synchronizeActiveSpaces()
        evaluateCurrentAppearance()
    }
}
