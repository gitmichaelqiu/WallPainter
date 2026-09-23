import XCTest

@testable import WallPainter

@MainActor
final class SpaceAPIDisconnectNotificationTests: XCTestCase {
    func testNotifiesOnlyForAvailableToUnavailableTransitionsWhenEnabled() async {
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let scheduler = TestDisconnectNotificationScheduler(authorizationGranted: true)
        let manager = SpaceAPIDisconnectNotificationManager(
            preferences: preferences,
            scheduler: scheduler
        )

        await manager.setEnabled(true)
        manager.availabilityDidChange(from: false, to: true)
        manager.availabilityDidChange(from: true, to: false)
        manager.availabilityDidChange(from: false, to: false)
        manager.availabilityDidChange(from: false, to: true)
        manager.availabilityDidChange(from: true, to: false)

        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertEqual(scheduler.notificationCount, 2)
        XCTAssertTrue(preferences.notifyOnSpaceAPIDisconnect)
        XCTAssertNil(manager.permissionMessage)
    }

    func testDoesNotNotifyWhilePreferenceIsOff() {
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let scheduler = TestDisconnectNotificationScheduler(authorizationGranted: true)
        let manager = SpaceAPIDisconnectNotificationManager(
            preferences: preferences,
            scheduler: scheduler
        )

        manager.availabilityDidChange(from: true, to: false)

        XCTAssertFalse(preferences.notifyOnSpaceAPIDisconnect)
        XCTAssertEqual(scheduler.notificationCount, 0)
        XCTAssertEqual(scheduler.requestCount, 0)
    }

    func testDeniedNotificationPermissionKeepsPreferenceOff() async {
        let preferences = WallPainterPreferences(defaults: makeDefaults())
        let scheduler = TestDisconnectNotificationScheduler(authorizationGranted: false)
        let manager = SpaceAPIDisconnectNotificationManager(
            preferences: preferences,
            scheduler: scheduler
        )

        await manager.setEnabled(true)

        XCTAssertFalse(preferences.notifyOnSpaceAPIDisconnect)
        XCTAssertNotNil(manager.permissionMessage)
        XCTAssertEqual(scheduler.notificationCount, 0)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SpaceAPIDisconnectNotificationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class TestDisconnectNotificationScheduler: SpaceAPIDisconnectNotificationScheduling {
    let authorizationGranted: Bool
    private(set) var requestCount = 0
    private(set) var notificationCount = 0

    init(authorizationGranted: Bool) {
        self.authorizationGranted = authorizationGranted
    }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        return authorizationGranted
    }

    func scheduleDisconnectNotification() {
        notificationCount += 1
    }
}
