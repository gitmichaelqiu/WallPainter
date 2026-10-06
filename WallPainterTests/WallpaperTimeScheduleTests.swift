import XCTest

@testable import WallPainter

final class WallpaperTimeScheduleTests: XCTestCase {
    func testAdjacentPeriodsDoNotOverlap() {
        let periods = [
            WallpaperTimePeriod(startMinute: 9 * 60, endMinute: 12 * 60),
            WallpaperTimePeriod(startMinute: 12 * 60, endMinute: 17 * 60)
        ]

        XCTAssertFalse(WallpaperTimeSchedule.hasOverlaps(periods))
        XCTAssertTrue(
            WallpaperTimeSchedule.isValid(
                periods.map { period in
                    var configuredPeriod = period
                    configuredPeriod.wallpaperID = "wallpaper"
                    return configuredPeriod
                },
                installedWallpaperIDs: ["wallpaper"]
            )
        )
    }

    func testOvernightPeriodsDetectOverlapAcrossMidnight() {
        let overnight = WallpaperTimePeriod(startMinute: 22 * 60, endMinute: 2 * 60)
        let overlapping = WallpaperTimePeriod(startMinute: 90, endMinute: 3 * 60)
        let adjacent = WallpaperTimePeriod(startMinute: 2 * 60, endMinute: 3 * 60)

        XCTAssertTrue(WallpaperTimeSchedule.hasOverlaps([overnight, overlapping]))
        XCTAssertFalse(WallpaperTimeSchedule.hasOverlaps([overnight, adjacent]))
    }

    func testInvalidPeriodsCannotBeSaved() {
        let period = WallpaperTimePeriod(
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            wallpaperID: "missing"
        )

        XCTAssertFalse(WallpaperTimeSchedule.isValid([], installedWallpaperIDs: ["missing"]))
        XCTAssertFalse(
            WallpaperTimeSchedule.isValid([period], installedWallpaperIDs: ["installed"])
        )
        XCTAssertFalse(
            WallpaperTimeSchedule.isValid(
                [WallpaperTimePeriod(startMinute: 600, endMinute: 600, wallpaperID: "installed")],
                installedWallpaperIDs: ["installed"]
            )
        )
    }

    func testScheduleResolvesInclusiveStartExclusiveEndAndOvernightTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let daytime = WallpaperTimePeriod(
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            wallpaperID: "day"
        )
        let overnight = WallpaperTimePeriod(
            startMinute: 22 * 60,
            endMinute: 2 * 60,
            wallpaperID: "night"
        )
        let rule = WallpaperRule.timeSchedule([daytime, overnight])

        XCTAssertEqual(
            rule.resolvedWallpaperID(
                for: .light,
                at: date(hour: 9, minute: 0, calendar: calendar),
                calendar: calendar
            ),
            "day"
        )
        XCTAssertEqual(
            rule.resolvedWallpaperID(
                for: .light,
                at: date(hour: 16, minute: 59, calendar: calendar),
                calendar: calendar
            ),
            "day"
        )
        XCTAssertNil(
            rule.resolvedWallpaperID(
                for: .light,
                at: date(hour: 17, minute: 0, calendar: calendar),
                calendar: calendar
            )
        )
        XCTAssertEqual(
            rule.resolvedWallpaperID(
                for: .dark,
                at: date(hour: 23, minute: 0, calendar: calendar),
                calendar: calendar
            ),
            "night"
        )
        XCTAssertEqual(
            rule.resolvedWallpaperID(
                for: .dark,
                at: date(hour: 1, minute: 59, calendar: calendar),
                calendar: calendar
            ),
            "night"
        )
        XCTAssertNil(
            rule.resolvedWallpaperID(
                for: .dark,
                at: date(hour: 2, minute: 0, calendar: calendar),
                calendar: calendar
            )
        )
    }

    func testOlderSavedRulesDecodeWithoutTimePeriods() throws {
        let data = Data(#"{"mode":"appearance","lightWallpaperID":"day","darkWallpaperID":"night"}"#.utf8)
        let rule = try JSONDecoder().decode(WallpaperRule.self, from: data)

        XCTAssertEqual(rule.mode, .appearance)
        XCTAssertEqual(rule.timePeriods, [])
    }

    func testTimeScheduleEncodesAndDecodes() throws {
        let rule = WallpaperRule.timeSchedule([
            WallpaperTimePeriod(
                startMinute: 8 * 60,
                endMinute: 12 * 60,
                wallpaperID: "morning"
            )
        ])

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(WallpaperRule.self, from: data)

        XCTAssertEqual(decoded, rule)
    }

    private func date(hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 15, hour: hour, minute: minute)
        )!
    }
}
