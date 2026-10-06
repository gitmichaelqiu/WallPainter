import Foundation

enum WallpaperRuleMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case manual
    case fixed
    case appearance
    case timeSchedule

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .manual:
            return "Manual"
        case .fixed:
            return "Fixed wallpaper"
        case .appearance:
            return "Follow system appearance"
        case .timeSchedule:
            return "Time schedule"
        }
    }
}

struct WallpaperTimePeriod: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var startMinute: Int
    var endMinute: Int
    var wallpaperID: String?

    init(
        id: UUID = UUID(),
        startMinute: Int,
        endMinute: Int,
        wallpaperID: String? = nil
    ) {
        self.id = id
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.wallpaperID = wallpaperID
    }

    var hasValidTimeRange: Bool {
        (0..<WallpaperTimeSchedule.minutesPerDay).contains(startMinute)
            && (0..<WallpaperTimeSchedule.minutesPerDay).contains(endMinute)
            && startMinute != endMinute
    }

    func contains(minuteOfDay: Int) -> Bool {
        guard hasValidTimeRange else { return false }
        if startMinute < endMinute {
            return (startMinute..<endMinute).contains(minuteOfDay)
        }
        return minuteOfDay >= startMinute || minuteOfDay < endMinute
    }

    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: date(for: startMinute))) – \(formatter.string(from: date(for: endMinute)))"
    }

    fileprivate var dailySegments: [Range<Int>] {
        guard hasValidTimeRange else { return [] }
        if startMinute < endMinute {
            return [startMinute..<endMinute]
        }

        return [startMinute..<WallpaperTimeSchedule.minutesPerDay]
            + (endMinute > 0 ? [0..<endMinute] : [])
    }

    private func date(for minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = .current
        components.timeZone = .current
        components.year = 2001
        components.month = 1
        components.day = 15
        components.hour = minute / 60
        components.minute = minute % 60
        return Calendar.current.date(from: components) ?? .now
    }
}

enum WallpaperTimeSchedule {
    static let minutesPerDay = 24 * 60

    static func hasOverlaps(_ periods: [WallpaperTimePeriod]) -> Bool {
        guard periods.count > 1 else { return false }

        for firstIndex in periods.indices {
            for secondIndex in periods.index(after: firstIndex)..<periods.endIndex {
                let first = periods[firstIndex]
                let second = periods[secondIndex]
                for firstSegment in first.dailySegments {
                    for secondSegment in second.dailySegments {
                        if firstSegment.overlaps(secondSegment) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    static func isValid(
        _ periods: [WallpaperTimePeriod],
        installedWallpaperIDs: Set<String>
    ) -> Bool {
        !periods.isEmpty
            && periods.allSatisfy { period in
                period.hasValidTimeRange
                    && period.wallpaperID.map(installedWallpaperIDs.contains) == true
            }
            && !hasOverlaps(periods)
    }
}

struct WallpaperRule: Codable, Equatable, Sendable {
    var mode: WallpaperRuleMode
    var fixedWallpaperID: String?
    var lightWallpaperID: String?
    var darkWallpaperID: String?
    var timePeriods: [WallpaperTimePeriod]

    private enum CodingKeys: String, CodingKey {
        case mode
        case fixedWallpaperID
        case lightWallpaperID
        case darkWallpaperID
        case timePeriods
    }

    init(
        mode: WallpaperRuleMode,
        fixedWallpaperID: String? = nil,
        lightWallpaperID: String? = nil,
        darkWallpaperID: String? = nil,
        timePeriods: [WallpaperTimePeriod] = []
    ) {
        self.mode = mode
        self.fixedWallpaperID = fixedWallpaperID
        self.lightWallpaperID = lightWallpaperID
        self.darkWallpaperID = darkWallpaperID
        self.timePeriods = timePeriods
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(WallpaperRuleMode.self, forKey: .mode)
        fixedWallpaperID = try values.decodeIfPresent(String.self, forKey: .fixedWallpaperID)
        lightWallpaperID = try values.decodeIfPresent(String.self, forKey: .lightWallpaperID)
        darkWallpaperID = try values.decodeIfPresent(String.self, forKey: .darkWallpaperID)
        timePeriods = try values.decodeIfPresent([WallpaperTimePeriod].self, forKey: .timePeriods) ?? []
    }

    static let emptyAppearance = WallpaperRule(
        mode: .appearance,
        fixedWallpaperID: nil,
        lightWallpaperID: nil,
        darkWallpaperID: nil,
        timePeriods: []
    )

    static let manual = WallpaperRule(
        mode: .manual,
        fixedWallpaperID: nil,
        lightWallpaperID: nil,
        darkWallpaperID: nil,
        timePeriods: []
    )

    static func fixed(_ wallpaperID: String? = nil) -> WallpaperRule {
        WallpaperRule(
            mode: .fixed,
            fixedWallpaperID: wallpaperID,
            lightWallpaperID: nil,
            darkWallpaperID: nil,
            timePeriods: []
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
            darkWallpaperID: darkWallpaperID,
            timePeriods: []
        )
    }

    static func timeSchedule(_ periods: [WallpaperTimePeriod] = []) -> WallpaperRule {
        WallpaperRule(mode: .timeSchedule, timePeriods: periods)
    }

    var referencedWallpaperIDs: Set<String> {
        switch mode {
        case .manual:
            return []
        case .fixed:
            return fixedWallpaperID.map { Set([$0]) } ?? []
        case .appearance:
            return Set([lightWallpaperID, darkWallpaperID].compactMap { $0 })
        case .timeSchedule:
            return Set(timePeriods.compactMap(\.wallpaperID))
        }
    }

    func isValid(installedWallpaperIDs: Set<String>) -> Bool {
        switch mode {
        case .manual:
            return true
        case .fixed:
            guard let fixedWallpaperID else { return false }
            return installedWallpaperIDs.contains(fixedWallpaperID)
        case .appearance:
            guard let lightWallpaperID, let darkWallpaperID else { return false }
            return installedWallpaperIDs.contains(lightWallpaperID)
                && installedWallpaperIDs.contains(darkWallpaperID)
        case .timeSchedule:
            return WallpaperTimeSchedule.isValid(
                timePeriods,
                installedWallpaperIDs: installedWallpaperIDs
            )
        }
    }

    func resolvedWallpaperID(
        for appearance: WallpaperAppearance,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        switch mode {
        case .manual:
            return nil
        case .fixed:
            return fixedWallpaperID
        case .appearance:
            switch appearance {
            case .light:
                return lightWallpaperID
            case .dark:
                return darkWallpaperID
            }
        case .timeSchedule:
            let components = calendar.dateComponents([.hour, .minute], from: date)
            guard let hour = components.hour, let minute = components.minute else { return nil }
            let minuteOfDay = hour * 60 + minute
            return timePeriods.first(where: { $0.contains(minuteOfDay: minuteOfDay) })?.wallpaperID
        }
    }
}

struct WallpaperSpaceTarget: Codable, Equatable, Hashable, Sendable {
    /// Stable DesktopRenamer identity used for saved rules and in-memory state.
    let spaceID: String
    let displayID: String
    /// Current macOS ManagedSpaceID used to resolve the wallpaper-store record.
    let managedSpaceID: String?

    init(spaceID: String, displayID: String, managedSpaceID: String? = nil) {
        self.spaceID = spaceID
        self.displayID = displayID
        self.managedSpaceID = managedSpaceID
    }

    init?(space: SpaceDescriptor) {
        guard let managedSpaceID = space.managedSpaceID else { return nil }
        self.init(
            spaceID: space.id,
            displayID: space.displayID,
            managedSpaceID: managedSpaceID
        )
    }
}

enum WallpaperActiveState: Equatable, Sendable {
    case unavailable
    case empty
    case uniform(String)
    case mixed
}
