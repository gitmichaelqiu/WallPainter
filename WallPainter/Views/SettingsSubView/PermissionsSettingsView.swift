import SwiftUI

struct PermissionsSettingsView: View {
    let spaceManager: SpaceAPIClient?

    var body: some View {
        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(
                    "Permissions",
                    helperText: "DesktopRenamer provides SpaceAPI. Enable it, then approve WallPainter with read-only access in DesktopRenamer's Settings → General → Advanced → Manage SpaceAPI access."
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
            case .connecting:
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to DesktopRenamer…")
                    .foregroundStyle(.secondary)
            case .accessDenied:
                Text("Approve WallPainter in DesktopRenamer's SpaceAPI settings.")
                    .foregroundStyle(.secondary)
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
    }
}
