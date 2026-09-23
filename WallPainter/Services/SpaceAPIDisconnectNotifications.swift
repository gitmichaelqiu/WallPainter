import Foundation
import UserNotifications

@MainActor
protocol SpaceAPIDisconnectNotificationScheduling {
    func requestAuthorization() async throws -> Bool
    func scheduleDisconnectNotification()
}

@MainActor
struct SystemSpaceAPIDisconnectNotificationScheduler:
    SpaceAPIDisconnectNotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func scheduleDisconnectNotification() {
        let content = UNMutableNotificationContent()
        content.title = "SpaceAPI disconnected"
        content.body = "Space-aware wallpaper changes are paused until "
            + "DesktopRenamer reconnects."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

@MainActor
final class SpaceAPIDisconnectNotificationManager {
    private let preferences: WallPainterPreferences
    private let scheduler: any SpaceAPIDisconnectNotificationScheduling

    private(set) var permissionMessage: String?

    init(
        preferences: WallPainterPreferences,
        scheduler: (any SpaceAPIDisconnectNotificationScheduling)? = nil
    ) {
        self.preferences = preferences
        self.scheduler = scheduler ?? SystemSpaceAPIDisconnectNotificationScheduler()
    }

    func setEnabled(_ enabled: Bool) async {
        permissionMessage = nil

        guard enabled else {
            preferences.notifyOnSpaceAPIDisconnect = false
            return
        }

        do {
            guard try await scheduler.requestAuthorization() else {
                permissionMessage = "Allow notifications for WallPainter in System Settings, "
                    + "then try again."
                return
            }

            preferences.notifyOnSpaceAPIDisconnect = true
        } catch {
            permissionMessage = "Could not request notification access: "
                + error.localizedDescription
        }
    }

    func availabilityDidChange(from wasAvailable: Bool, to isAvailable: Bool) {
        guard wasAvailable, !isAvailable,
              preferences.notifyOnSpaceAPIDisconnect
        else { return }

        scheduler.scheduleDisconnectNotification()
    }
}
