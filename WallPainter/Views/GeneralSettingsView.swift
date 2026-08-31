import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: WallpaperModel
    let launchAtLoginManager: any LaunchAtLoginManaging
    let spaceProvider: (any SpaceAPIProviding)?

    @Environment(WallPainterPreferences.self) private var preferences
    @State private var launchAtLoginEnabled = false
    @State private var hasLoadedLaunchAtLogin = false
    @State private var snapshot: SpaceSnapshot?

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
                        Text(currentWallpaperStatus)
                            .foregroundStyle(
                                isWallpaperActive ? Color.green : Color.secondary
                            )
                            .frame(minHeight: 24)
                    }

                    Divider()

                    SettingsRow("Active spaces") {
                        Text(activeSpaceSummary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 240, alignment: .trailing)
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

                SettingsSection("Apply Wallpaper") {
                    SettingsRow("Apply to current space(s)") {
                        Button {
                            applyToCurrentSpaces()
                        } label: {
                            if model.isSwitching {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Switching…")
                            } else {
                                Label("Apply", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .disabled(!canApplyToCurrentSpaces || model.isSwitching)
                    }

                    Divider()

                    SettingsRow("Apply Everywhere") {
                        Button {
                            applyEverywhere()
                        } label: {
                            Label("Apply", systemImage: "square.grid.3x3.fill")
                        }
                        .disabled(model.selectedWallpaper == nil || model.isSwitching)
                    }
                }

                SettingsSection("General") {
                    SettingsRow("Hide menubar icon") {
                        Toggle("", isOn: $preferences.hideMenuBarIcon)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow("Launch at login") {
                        Toggle("", isOn: $launchAtLoginEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
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
            updateSpaceState()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .wallPainterSpaceSnapshotDidChange
        )) { _ in
            updateSpaceState()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .wallPainterSpaceAvailabilityDidChange
        )) { _ in
            updateSpaceState()
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

    private var regularSpaces: [SpaceDescriptor] {
        snapshot?.spaces.filter { !$0.isFullscreen } ?? []
    }

    private var currentSpaces: [SpaceDescriptor] {
        guard let snapshot else { return [] }
        let spacesByID = Dictionary(uniqueKeysWithValues: regularSpaces.map { ($0.id, $0) })
        return snapshot.currentSpaceIDs.compactMap { spacesByID[$0] }
    }

    private var currentTargets: [WallpaperSpaceTarget] {
        currentSpaces.map {
            WallpaperSpaceTarget(spaceID: $0.id, displayID: $0.displayID)
        }
    }

    private var allSpaceTargets: [WallpaperSpaceTarget] {
        regularSpaces.map {
            WallpaperSpaceTarget(spaceID: $0.id, displayID: $0.displayID)
        }
    }

    private var currentWallpaperStatus: String {
        switch model.currentWallpaperState {
        case .empty, .unavailable:
            return "Unavailable"
        case .uniform, .mixed:
            return "Active"
        }
    }

    private var isWallpaperActive: Bool {
        switch model.currentWallpaperState {
        case .uniform, .mixed:
            return true
        case .empty, .unavailable:
            return false
        }
    }

    private var activeSpaceSummary: String {
        guard spaceProvider != nil else { return "Unavailable" }
        guard snapshot != nil else { return "Unavailable" }
        guard !currentSpaces.isEmpty else { return "None detected" }
        if currentSpaces.count == 1 {
            return currentSpaces[0].name
        }
        return "\(currentSpaces.count) active spaces"
    }

    private var canApplyToCurrentSpaces: Bool {
        spaceProvider?.isAvailable == true && !currentTargets.isEmpty
    }

    private func updateSpaceState() {
        snapshot = spaceProvider?.snapshot
        guard !currentTargets.isEmpty else { return }
        model.synchronizeCurrentWallpapers(for: currentTargets)
    }

    private func applyToCurrentSpaces() {
        guard let wallpaperID = model.selectedWallpaperID else { return }
        updateSpaceState()
        _ = model.applyWallpaper(id: wallpaperID, to: currentTargets)
    }

    private func applyEverywhere() {
        guard let wallpaperID = model.selectedWallpaperID else { return }

        if spaceProvider?.isAvailable == true, !allSpaceTargets.isEmpty {
            model.synchronizeWallpaperIDs(for: allSpaceTargets)
            _ = model.applyWallpaper(id: wallpaperID, to: allSpaceTargets)
        } else {
            _ = model.applyWallpaperEverywhere(id: wallpaperID)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : .clear)

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
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
