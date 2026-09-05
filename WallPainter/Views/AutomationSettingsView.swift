import SwiftUI

struct DefaultSettingsView: View {
    let model: WallpaperModel
    let coordinator: WallpaperAutomationCoordinator
    let spaceProvider: (any SpaceAPIProviding)?

    @Environment(WallPainterPreferences.self) private var preferences
    @State private var isSpaceAPIAvailable = false

    var body: some View {
        @Bindable var preferences = preferences

        SettingsContainer(.default) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(
                    "Default Wallpaper",
                    helperText: "Spaces use this behavior unless they have their own override."
                ) {
                    SettingsRow("Rule") {
                        Picker("", selection: $preferences.defaultWallpaperRule.mode) {
                            ForEach(WallpaperRuleMode.allCases) { mode in
                                Text(mode.displayName)
                                    .tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 190, alignment: .trailing)
                    }

                    Divider()

                    if preferences.defaultWallpaperRule.mode == .manual {
                        SettingsRow("Automatic changes") {
                            Text("Off")
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 24)
                        }
                    } else if preferences.defaultWallpaperRule.mode == .fixed {
                        SettingsRow("Fixed wallpaper") {
                            WallpaperPicker(
                                selection: $preferences.defaultWallpaperRule.fixedWallpaperID,
                                wallpapers: model.items
                            )
                        }
                    } else {
                        SettingsRow("Light wallpaper") {
                            WallpaperPicker(
                                selection: $preferences.defaultWallpaperRule.lightWallpaperID,
                                wallpapers: model.items
                            )
                        }

                        Divider()

                        SettingsRow("Dark wallpaper") {
                            WallpaperPicker(
                                selection: $preferences.defaultWallpaperRule.darkWallpaperID,
                                wallpapers: model.items
                            )
                        }
                    }

                    Divider()

                    WallpaperRulePreview(
                        rule: preferences.defaultWallpaperRule,
                        wallpapers: model.items,
                        title: "Preview"
                    )
                }

                SettingsSection("Status") {
                    SettingsRow("Current system appearance") {
                        Text(coordinator.currentAppearance.displayName)
                            .frame(minHeight: 24)
                    }

                    Divider()

                    SettingsRow(
                        "SpaceAPI availability",
                        warningText: isSpaceAPIAvailable
                            ? nil
                            : "Space-aware automation pauses while DesktopRenamer SpaceAPI is unavailable."
                    ) {
                        Text(isSpaceAPIAvailable ? "Available" : "Unavailable")
                            .foregroundStyle(
                                isSpaceAPIAvailable ? Color.green : Color.secondary
                            )
                            .frame(minHeight: 24)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            updateSpaceAPIAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .wallPainterSpaceAvailabilityDidChange
        )) { _ in
            updateSpaceAPIAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .wallPainterSpaceSnapshotDidChange
        )) { _ in
            updateSpaceAPIAvailability()
        }
    }

    private func updateSpaceAPIAvailability() {
        isSpaceAPIAvailable = spaceProvider?.isAvailable == true
    }
}

struct WallpaperPicker: View {
    @Binding var selection: String?
    let wallpapers: [WallpaperItem]

    var body: some View {
        Picker("", selection: $selection) {
            Text("Not selected")
                .tag(Optional<String>.none)

            if let selection,
               !wallpapers.contains(where: { $0.id == selection }) {
                Text("Unavailable")
                    .tag(Optional(selection))
            }

            ForEach(wallpapers) { wallpaper in
                Text(wallpaper.name)
                    .tag(Optional(wallpaper.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 190, alignment: .trailing)
    }
}
