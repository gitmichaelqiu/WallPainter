import SwiftUI

struct PermissionsSettingsView: View {
    let spaceManager: SpaceAPIClient?

    @Environment(WallPainterPreferences.self) private var preferences
    @State private var notificationPermissionMessage: String?
    @State private var isRequestingNotificationPermission = false

    var body: some View {
        @Bindable var preferences = preferences

        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(
                    "Permissions",
                    helperText: "DesktopRenamer provides SpaceAPI. Enable it in DesktopRenamer's settings before using space-aware wallpaper rules."
                ) {
                    SettingsRow(
                        "DesktopRenamer SpaceAPI"
                    ) {
                        if let spaceManager {
                            SpaceAPIStatusView(spaceManager: spaceManager)
                        } else {
                            HStack(spacing: 8) {
                                PermissionStatusIcon(isGranted: false)
                                Text("Unavailable")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(height: 24)
                        }
                    }

                    Divider()

                    SettingsRow(
                        "Notify on disconnect",
                        helperText: "Send a macOS notification when a previously available SpaceAPI connection drops. Requires notification access."
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { preferences.notifyOnSpaceAPIDisconnect },
                                set: { enabled in
                                    guard let manager = spaceManager?
                                        .disconnectNotificationManager
                                    else {
                                        return
                                    }
                                    isRequestingNotificationPermission = true
                                    Task { @MainActor in
                                        defer {
                                            isRequestingNotificationPermission = false
                                        }
                                        await manager.setEnabled(enabled)
                                        notificationPermissionMessage = manager.permissionMessage
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(spaceManager == nil || isRequestingNotificationPermission)
                    }

                    if let notificationPermissionMessage {
                        Divider()

                        SettingsRow("Notification access") {
                            Text(notificationPermissionMessage)
                                .foregroundStyle(.orange)
                                .frame(minHeight: 24)
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct PermissionStatusIcon: View {
    let isGranted: Bool

    var body: some View {
        Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(isGranted ? Color.green : Color.red)
    }
}

private struct SpaceAPIStatusView: View {
    let spaceManager: SpaceAPIClient

    var body: some View {
        HStack(spacing: 8) {
            PermissionStatusIcon(isGranted: spaceManager.apiAvailability == .available)

            switch spaceManager.apiAvailability {
            case .available, .disabled:
                Button("Open DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
            case .unavailable:
                Button("Launch DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
                .disabled(spaceManager.desktopRenamerApplicationURL == nil)

                Button("Install DesktopRenamer") {
                    spaceManager.openDesktopRenamerDownloadPage()
                }
            }
        }
        .frame(height: 24)
    }
}
