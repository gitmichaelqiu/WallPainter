import Foundation
import Observation

struct ManualWallpaperHold: Codable, Equatable, Sendable {
    let wallpaperID: String
    let ruleWallpaperID: String?
}

@MainActor
@Observable
final class WallPainterPreferences {
    static let selectedWallpaperKey = "WallPainter.selectedWallpaperID"
    static let showStatusBarItemKey = "WallPainter.showStatusBarItem"
    static let wallpaperProtectionEnabledKey = "WallPainter.wallpaperProtectionEnabled"
    static let notifyOnSpaceAPIDisconnectKey = "WallPainter.notifyOnSpaceAPIDisconnect"
    static let defaultWallpaperRuleKey = "WallPainter.defaultWallpaperRule"
    static let spaceOverridesKey = "WallPainter.spaceOverrides"
    static let manualWallpaperHoldsKey = "WallPainter.manualWallpaperHoldsBySpaceID"

    @ObservationIgnored private let defaults: UserDefaults

    var selectedWallpaperID: String? {
        didSet {
            persist(selectedWallpaperID, forKey: Self.selectedWallpaperKey)
            postChange()
        }
    }

    var showStatusBarItem: Bool {
        didSet {
            defaults.set(showStatusBarItem, forKey: Self.showStatusBarItemKey)
            postChange()
        }
    }

    var wallpaperProtectionEnabled: Bool {
        didSet {
            defaults.set(
                wallpaperProtectionEnabled,
                forKey: Self.wallpaperProtectionEnabledKey
            )
            postChange()
        }
    }

    var notifyOnSpaceAPIDisconnect: Bool {
        didSet {
            defaults.set(
                notifyOnSpaceAPIDisconnect,
                forKey: Self.notifyOnSpaceAPIDisconnectKey
            )
            postChange()
        }
    }

    var hideMenuBarIcon: Bool {
        get { !showStatusBarItem }
        set { showStatusBarItem = !newValue }
    }

    var defaultWallpaperRule: WallpaperRule {
        didSet {
            persist(defaultWallpaperRule, forKey: Self.defaultWallpaperRuleKey)
            postChange()
        }
    }

    private(set) var spaceOverrides: [String: WallpaperRule] {
        didSet {
            persist(spaceOverrides, forKey: Self.spaceOverridesKey)
            postChange()
        }
    }

    private(set) var manualWallpaperHoldsBySpaceID: [String: ManualWallpaperHold] {
        didSet {
            persist(manualWallpaperHoldsBySpaceID, forKey: Self.manualWallpaperHoldsKey)
            postChange()
        }
    }

    var protectedWallpaperIDs: Set<String> {
        var IDs = defaultWallpaperRule.referencedWallpaperIDs
        for rule in spaceOverrides.values {
            IDs.formUnion(rule.referencedWallpaperIDs)
        }
        IDs.formUnion(manualWallpaperHoldsBySpaceID.values.map(\.wallpaperID))
        if let selectedWallpaperID {
            IDs.insert(selectedWallpaperID)
        }
        return IDs
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedWallpaperID = defaults.string(forKey: Self.selectedWallpaperKey)
        showStatusBarItem = defaults.object(forKey: Self.showStatusBarItemKey) as? Bool ?? true
        wallpaperProtectionEnabled = defaults.object(
            forKey: Self.wallpaperProtectionEnabledKey
        ) as? Bool ?? true
        notifyOnSpaceAPIDisconnect = defaults.object(
            forKey: Self.notifyOnSpaceAPIDisconnectKey
        ) as? Bool ?? false
        defaultWallpaperRule = Self.decode(
            WallpaperRule.self,
            from: defaults,
            key: Self.defaultWallpaperRuleKey
        ) ?? .manual

        spaceOverrides = Self.decode(
            [String: WallpaperRule].self,
            from: defaults,
            key: Self.spaceOverridesKey
        ) ?? [:]

        manualWallpaperHoldsBySpaceID = Self.decode(
            [String: ManualWallpaperHold].self,
            from: defaults,
            key: Self.manualWallpaperHoldsKey
        ) ?? [:]
    }

    func spaceRule(for spaceID: String) -> WallpaperRule? {
        spaceOverrides[spaceID]
    }

    func setSpaceRule(_ rule: WallpaperRule?, for spaceID: String) {
        guard !spaceID.isEmpty else { return }

        if let rule {
            spaceOverrides[spaceID] = rule
        } else {
            spaceOverrides.removeValue(forKey: spaceID)
        }
    }

    func setManualWallpaperHolds(_ holds: [String: ManualWallpaperHold]) {
        guard !holds.isEmpty else { return }
        var updatedHolds = manualWallpaperHoldsBySpaceID
        updatedHolds.merge(holds) { _, new in new }
        guard updatedHolds != manualWallpaperHoldsBySpaceID else { return }
        manualWallpaperHoldsBySpaceID = updatedHolds
    }

    func clearManualWallpaperHolds(forSpaceIDs spaceIDs: Set<String>) {
        guard !spaceIDs.isEmpty else { return }
        var updatedHolds = manualWallpaperHoldsBySpaceID
        for spaceID in spaceIDs {
            updatedHolds.removeValue(forKey: spaceID)
        }
        guard updatedHolds != manualWallpaperHoldsBySpaceID else { return }
        manualWallpaperHoldsBySpaceID = updatedHolds
    }

    @discardableResult
    func migrateLegacySpaceOverrides(using spaces: [SpaceDescriptor]) -> Int {
        var spacesByManagedID: [String: [SpaceDescriptor]] = [:]
        for space in spaces {
            guard let managedSpaceID = space.managedSpaceID else { continue }
            spacesByManagedID[managedSpaceID, default: []].append(space)
        }

        var migratedOverrides = spaceOverrides
        var migratedCount = 0
        for (legacySpaceID, rule) in spaceOverrides {
            // Previous WallPainter releases used numeric ManagedSpaceIDs as
            // preference keys. Keep nonnumeric stable IDs exactly as saved.
            guard Int(legacySpaceID) != nil,
                  let matches = spacesByManagedID[legacySpaceID],
                  matches.count == 1,
                  let space = matches.first,
                  space.id != legacySpaceID
            else { continue }

            if let existingRule = migratedOverrides[space.id], existingRule != rule {
                // A current stable-ID rule wins; retain the old entry rather
                // than discard conflicting user data.
                continue
            }

            migratedOverrides[space.id] = rule
            migratedOverrides.removeValue(forKey: legacySpaceID)
            migratedCount += 1
        }

        if migratedCount > 0 {
            spaceOverrides = migratedOverrides
        }
        return migratedCount
    }

    func resetSpaceOverrides() {
        guard !spaceOverrides.isEmpty else { return }
        spaceOverrides = [:]
    }

    private func persist(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from defaults: UserDefaults,
        key: String
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func postChange() {
        NotificationCenter.default.post(
            name: .wallPainterPreferencesDidChange,
            object: self
        )
    }
}

extension Notification.Name {
    static let wallPainterPreferencesDidChange = Notification.Name(
        "WallPainter.preferencesDidChange"
    )
}
