import SwiftUI

struct AutomationSettingsView: View {
    let model: WallpaperModel
    let coordinator: WallpaperAutomationCoordinator

    @Environment(WallPainterPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        SettingsContainer(.automation) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(
                    "Wallpaper Automation",
                    helperText: "Use a different installed wallpaper for Light and Dark system appearances."
                ) {
                    SettingsRow(
                        "Enable Automatic Switching",
                        warningText: coordinator.hasValidMappings
                            ? nil
                            : "Select an installed wallpaper for both Light and Dark before enabling automation."
                    ) {
                        Toggle("", isOn: $preferences.automationEnabled)
                            .labelsHidden()
                            .disabled(!coordinator.hasValidMappings)
                    }

                    Divider()

                    SettingsRow("Current system appearance") {
                        Text(coordinator.currentAppearance.displayName)
                            .frame(minHeight: 24)
                    }
                }

                SettingsSection("Theme Wallpapers") {
                    SettingsRow("Light wallpaper") {
                        WallpaperAppearancePicker(
                            selection: $preferences.automationLightWallpaperID,
                            wallpapers: model.items
                        )
                    }

                    Divider()

                    SettingsRow("Dark wallpaper") {
                        WallpaperAppearancePicker(
                            selection: $preferences.automationDarkWallpaperID,
                            wallpapers: model.items
                        )
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct WallpaperAppearancePicker: View {
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
        .frame(minWidth: 180, alignment: .trailing)
    }
}
