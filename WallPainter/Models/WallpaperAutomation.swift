import AppKit
import Foundation
import Observation

enum WallpaperAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
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
    @ObservationIgnored private var catalogObserver: NSObjectProtocol?
    @ObservationIgnored private var preferencesObserver: NSObjectProtocol?
    @ObservationIgnored private var lastAttemptedAutomaticID: String?

    init(
        model: WallpaperModel,
        preferences: WallPainterPreferences,
        appearanceMonitor: (any AppearanceMonitoring)? = nil
    ) {
        self.model = model
        self.preferences = preferences
        self.appearanceMonitor = appearanceMonitor ?? SystemAppearanceMonitor()
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

        appearanceMonitor.start { [weak self] appearance in
            self?.appearanceDidChange(appearance)
        }
        evaluateCurrentAppearance()
    }

    func stop() {
        guard isRunning else { return }
        appearanceMonitor.stop()

        let notificationCenter = NotificationCenter.default
        if let catalogObserver {
            notificationCenter.removeObserver(catalogObserver)
        }
        if let preferencesObserver {
            notificationCenter.removeObserver(preferencesObserver)
        }
        self.catalogObserver = nil
        self.preferencesObserver = nil
        isRunning = false
    }

    var hasValidMappings: Bool {
        guard let lightID = preferences.automationLightWallpaperID,
              let darkID = preferences.automationDarkWallpaperID
        else {
            return false
        }

        return model.items.contains { $0.id == lightID }
            && model.items.contains { $0.id == darkID }
    }

    func targetWallpaperID(for appearance: WallpaperAppearance) -> String? {
        switch appearance {
        case .light:
            return preferences.automationLightWallpaperID
        case .dark:
            return preferences.automationDarkWallpaperID
        }
    }

    func evaluateCurrentAppearance() {
        guard preferences.automationEnabled else { return }

        guard hasValidMappings else {
            preferences.automationEnabled = false
            return
        }

        guard let targetID = targetWallpaperID(for: currentAppearance) else { return }

        if model.currentWallpaperID == targetID {
            lastAttemptedAutomaticID = nil
            if model.selectedWallpaperID != targetID {
                model.selectedWallpaperID = targetID
            }
            return
        }

        guard lastAttemptedAutomaticID != targetID else { return }

        lastAttemptedAutomaticID = targetID
        _ = model.applyWallpaper(id: targetID)
    }

    private func appearanceDidChange(_ appearance: WallpaperAppearance) {
        lastAttemptedAutomaticID = nil
        currentAppearance = appearance
        evaluateCurrentAppearance()
    }

    private func catalogDidChange() {
        lastAttemptedAutomaticID = nil
        evaluateCurrentAppearance()
    }

    private func preferencesDidChange() {
        lastAttemptedAutomaticID = nil
        evaluateCurrentAppearance()
    }
}
