import SwiftUI

struct PermissionsSettingsView: View {
    let spaceManager: SpaceAPIClient?

    var body: some View {
        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(
                    "Permissions",
                    helperText: "DesktopRenamer provides SpaceAPI. Enable it in DesktopRenamer's settings before using space-aware wallpaper rules."
                ) {
                    SettingsRow(
                        "DesktopRenamer SpaceAPI",
                        helperText: "Required for reading desktop spaces and applying space-based wallpaper rules."
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
