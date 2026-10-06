import Sparkle
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: WallpaperModel
    let launchAtLoginManager: any LaunchAtLoginManaging

    @Environment(WallPainterPreferences.self) private var preferences
    @State private var launchAtLoginEnabled = false
    @State private var hasLoadedLaunchAtLogin = false
    @State private var automaticallyChecksForUpdates = false
    @State private var automaticallyDownloadsUpdates = false

    var body: some View {
        @Bindable var preferences = preferences

        SettingsContainer(.general) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("App behavior") {
                    SettingsRow("Show menu bar icon") {
                        Toggle(
                            "Show menu bar icon",
                            isOn: Binding(
                                get: { !preferences.hideMenuBarIcon },
                                set: { preferences.hideMenuBarIcon = !$0 }
                            )
                        )
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow("Launch at login") {
                        Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(!hasLoadedLaunchAtLogin)
                    }
                }

                SettingsSection("Updates") {
                    SettingsRow("Automatically check for updates") {
                        Toggle(
                            "Automatically check for updates",
                            isOn: $automaticallyChecksForUpdates
                        )
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if automaticallyChecksForUpdates {
                        Divider()

                        SettingsRow("Automatically download updates") {
                            Toggle(
                                "Automatically download updates",
                                isOn: $automaticallyDownloadsUpdates
                            )
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(!UpdateManager.shared.updaterController.updater.allowsAutomaticUpdates)
                        }
                    }

                    Divider()

                    SettingsRow("Check for updates") {
                        Button("Check") {
                            UpdateManager.shared.updaterController.checkForUpdates(nil)
                        }
                    }
                }

                SettingsSection("Wallpaper Protection") {
                    SettingsRow(
                        "Wallpaper protection",
                        helperText: "Keep backups of configured wallpapers and restore them if macOS removes them."
                    ) {
                        Toggle(
                            "Wallpaper protection",
                            isOn: Binding(
                                get: { preferences.wallpaperProtectionEnabled },
                                set: { model.setWallpaperProtectionEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow("Status") {
                        if let removalError = model.protectionBackupRemovalError {
                            HStack(spacing: 8) {
                                Text("Couldn't remove backups")
                                    .foregroundStyle(.orange)

                                Button("Retry") {
                                    model.retryWallpaperProtectionCleanup()
                                }
                                .help(removalError)
                            }
                        } else if !preferences.wallpaperProtectionEnabled {
                            Text("Off")
                                .foregroundStyle(.secondary)
                        } else if model.assetProtectionStatus.isHealthy {
                            let status = model.assetProtectionStatus
                            let storageSize = ByteCountFormatter.string(
                                fromByteCount: status.backupSizeInBytes,
                                countStyle: .file
                            )
                            Text("\(status.protectedIDs.count) wallpapers (\(storageSize))")
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 8) {
                                Text("Repair needed")
                                    .foregroundStyle(.orange)

                                Button("Repair") {
                                    model.reconcileProtectedAssets()
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            hasLoadedLaunchAtLogin = true
            automaticallyChecksForUpdates = UpdateManager.shared
                .updaterController.updater.automaticallyChecksForUpdates
            automaticallyDownloadsUpdates = UpdateManager.shared
                .updaterController.updater.automaticallyDownloadsUpdates
        }
        .onChange(of: launchAtLoginEnabled) { _, newValue in
            guard hasLoadedLaunchAtLogin else { return }

            do {
                try launchAtLoginManager.setEnabled(newValue)
            } catch {
                launchAtLoginEnabled = launchAtLoginManager.isEnabled
            }
        }
        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
            UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates = newValue
            if !newValue {
                automaticallyDownloadsUpdates = false
            }
        }
        .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
            UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates = newValue
        }
    }
}
