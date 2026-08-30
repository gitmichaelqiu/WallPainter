import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: WallpaperModel
    let launchAtLoginManager: any LaunchAtLoginManaging

    @Environment(WallPainterPreferences.self) private var preferences
    @State private var launchAtLoginEnabled = false
    @State private var hasLoadedLaunchAtLogin = false

    var body: some View {
        @Bindable var preferences = preferences

        SettingsContainer(.general) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Current Wallpaper") {
                    SettingsRow("Current desktop wallpaper") {
                        Text(model.currentWallpaperName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220, alignment: .trailing)
                            .frame(minHeight: 24)
                    }

                    Divider()

                    SettingsRow("Status") {
                        Text(model.currentWallpaperID == nil ? "Unavailable" : "Active")
                            .foregroundStyle(
                                model.currentWallpaperID == nil ? Color.secondary : Color.green
                            )
                            .frame(minHeight: 24)
                    }
                }

                SettingsSection(
                    "Installed Live Wallpapers",
                    helperText: "Only Apple Aerial wallpapers already downloaded by macOS are shown here."
                ) {
                    SettingsRow("Refresh catalog") {
                        Button {
                            model.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isLoading)
                    }

                    Divider()

                    WallpaperCatalogContent(
                        wallpapers: model.items,
                        selection: $model.selectedWallpaperID,
                        isLoading: model.isLoading
                    )
                    .padding(10)
                }

                SettingsSection {
                    SettingsRow("Apply wallpaper") {
                        Button {
                            model.switchSelectedWallpaper()
                        } label: {
                            if model.isSwitching {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Switching…")
                            } else {
                                Label("Set as Desktop Wallpaper", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedWallpaper == nil || model.isSwitching)
                    }
                }

                if let status = model.operationStatus {
                    SettingsSection {
                        SettingsRow("Last operation") {
                            Label(status.message, systemImage: status.symbolName)
                                .foregroundStyle(status.isSuccess ? .green : .orange)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                SettingsSection("Application") {
                    SettingsRow("Show Status Bar Item") {
                        Toggle("", isOn: $preferences.showStatusBarItem)
                            .labelsHidden()
                    }

                    Divider()

                    SettingsRow("Launch at Login") {
                        Toggle("", isOn: $launchAtLoginEnabled)
                            .labelsHidden()
                            .disabled(!hasLoadedLaunchAtLogin)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            hasLoadedLaunchAtLogin = true
        }
        .onChange(of: launchAtLoginEnabled) { _, newValue in
            guard hasLoadedLaunchAtLogin else { return }

            do {
                try launchAtLoginManager.setEnabled(newValue)
            } catch {
                launchAtLoginEnabled = launchAtLoginManager.isEnabled
            }
        }
    }
}

private struct WallpaperCatalogContent: View {
    let wallpapers: [WallpaperItem]
    @Binding var selection: String?
    let isLoading: Bool

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if wallpapers.isEmpty {
            EmptyWallpaperCatalogView()
        } else {
            WallpaperGrid(wallpapers: wallpapers, selection: $selection)
        }
    }
}

private struct WallpaperGrid: View {
    let wallpapers: [WallpaperItem]
    @Binding var selection: String?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(wallpapers) { wallpaper in
                WallpaperCard(
                    wallpaper: wallpaper,
                    isSelected: selection == wallpaper.id
                ) {
                    selection = wallpaper.id
                }
            }
        }
    }
}

private struct WallpaperCard: View {
    let wallpaper: WallpaperItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                WallpaperThumbnail(url: wallpaper.thumbnailURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .clipShape(.rect(cornerRadius: 9))

                HStack(spacing: 7) {
                    Text(wallpaper.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }

                Text("Installed Apple Aerial")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(wallpaper.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Select this installed live wallpaper")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WallpaperThumbnail: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.blue.opacity(0.65), Color.indigo.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(.black.opacity(0.25), in: Circle())
            }
        }
        .clipped()
        .task(id: url) {
            image = url.flatMap { NSImage(contentsOf: $0) }
        }
        .accessibilityHidden(true)
    }
}

private struct EmptyWallpaperCatalogView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.slash")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No installed Aerial wallpapers found")
                .font(.headline)
            Text("Download an Apple Aerial in System Settings, then refresh this catalog.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding()
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }
}
