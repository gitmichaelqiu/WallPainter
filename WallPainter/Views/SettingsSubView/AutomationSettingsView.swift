import SwiftUI

struct DefaultSettingsView: View {
    let model: WallpaperModel
    let spaceProvider: (any SpaceAPIProviding)?

    @Environment(WallPainterPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        SettingsContainer(.default) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(
                    "Automatic Wallpaper Rule",
                    helperText: "Automatically applies to spaces using Default. Manual changes do not edit this rule and may be replaced the next time it runs."
                ) {
                    SettingsRow("Behavior") {
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

                    if hasAutomaticRules {
                        Divider()

                        SettingsRow(
                            "SpaceAPI",
                            helperText: "Required for applying automatic wallpaper rules to spaces. Reconnect it in Permissions if unavailable."
                        ) {
                            Text(spaceProvider?.isAvailable == true ? "Connected" : "Paused")
                                .foregroundStyle(
                                    spaceProvider?.isAvailable == true
                                        ? Color.secondary
                                        : Color.orange
                                )
                                .frame(minHeight: 24)
                        }
                    }

                    if preferences.defaultWallpaperRule.mode != .manual {
                        Divider()

                        if preferences.defaultWallpaperRule.mode == .fixed {
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
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var hasAutomaticRules: Bool {
        preferences.defaultWallpaperRule.mode != .manual
            || preferences.spaceOverrides.values.contains { $0.mode != .manual }
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
