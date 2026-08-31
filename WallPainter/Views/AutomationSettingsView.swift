import SwiftUI

struct AutomationSettingsView: View {
    let model: WallpaperModel
    let coordinator: WallpaperAutomationCoordinator
    let spaceProvider: (any SpaceAPIProviding)?

    @Environment(WallPainterPreferences.self) private var preferences
    @State private var isSpaceAPIAvailable = false

    private var installedWallpaperIDs: Set<String> {
        Set(model.items.map(\.id))
    }

    private var isDefaultRuleValid: Bool {
        preferences.automationDefaultRule.isValid(
            installedWallpaperIDs: installedWallpaperIDs
        )
    }

    var body: some View {
        @Bindable var preferences = preferences

        SettingsContainer(.automation) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Automation") {
                    SettingsRow(
                        "Enable Automatic Switching",
                        warningText: isDefaultRuleValid
                            ? nil
                            : "Select the wallpaper mapping for All Spaces before enabling automation."
                    ) {
                        Toggle("", isOn: $preferences.automationEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(!isDefaultRuleValid)
                    }
                }

                SettingsSection("All Spaces") {
                    SettingsRow("Wallpaper behavior") {
                        Picker("", selection: $preferences.automationDefaultRule.mode) {
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

                    if preferences.automationDefaultRule.mode == .fixed {
                        SettingsRow("Fixed wallpaper") {
                            WallpaperPicker(
                                selection: $preferences.automationDefaultRule.fixedWallpaperID,
                                wallpapers: model.items
                            )
                        }
                    } else {
                        SettingsRow("Light wallpaper") {
                            WallpaperPicker(
                                selection: $preferences.automationDefaultRule.lightWallpaperID,
                                wallpapers: model.items
                            )
                        }

                        Divider()

                        SettingsRow("Dark wallpaper") {
                            WallpaperPicker(
                                selection: $preferences.automationDefaultRule.darkWallpaperID,
                                wallpapers: model.items
                            )
                        }
                    }
                }

                SettingsSection("Current Status") {
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
        .onChange(of: isDefaultRuleValid) { _, isValid in
            if !isValid, preferences.automationEnabled {
                preferences.automationEnabled = false
            }
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
