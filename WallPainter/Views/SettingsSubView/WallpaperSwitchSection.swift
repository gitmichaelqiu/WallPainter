import SwiftUI

struct WallpaperSwitchSection: View {
    @Bindable var model: WallpaperModel
    let automationCoordinator: WallpaperAutomationCoordinator
    let spaceProvider: (any SpaceAPIProviding)?
    let onOpenPermissions: () -> Void

    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @State private var snapshot: SpaceSnapshot?
    @StateObject private var catalogScrollSession = CatalogScrollSession()
    @State private var statusSelectionID: String?

    private let wallpaperCatalogMaxHeight: CGFloat = 340

    var body: some View {
        SettingsSection(
            "Switch Once",
            helperText: "Changes the wallpaper without editing any rules. Each manual selection stays active until that space’s rule selects a different wallpaper."
        ) {
            SettingsRow("Currently active") {
                Text(model.currentWallpaperSummary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .trailing)
            }

            Divider()

            SettingsRow("Refresh catalog") {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16, height: 16)
                }
                .accessibilityLabel("Refresh catalog")
                .disabled(model.isLoading)
            }

            Divider()

            WallpaperCatalogScrollView(
                wallpapers: model.items,
                selection: $model.selectedWallpaperID,
                isLoading: model.isLoading,
                scrollSession: catalogScrollSession,
                isPreRendering: isPreRendering,
                maxHeight: wallpaperCatalogMaxHeight
            )

            Divider()

            SettingsRow("Switch wallpaper") {
                HStack(spacing: 8) {
                    Button(activeSpacesButtonTitle) {
                        switchOnActiveSpaces()
                    }
                    .accessibilityLabel("Switch wallpaper on active spaces")
                    .disabled(!canSwitchOnActiveSpaces || !canSwitchSelection)

                    Button(allSpacesButtonTitle) {
                        switchOnAllSpaces()
                    }
                    .accessibilityLabel("Switch wallpaper on all spaces")
                    .disabled(!canSwitchSelection)
                }
            }

            if !canSwitchOnActiveSpaces {
                Divider()

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeSpaceUnavailableTitle)
                            .font(.subheadline)
                        Text(activeSpaceUnavailableMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if spaceProvider?.isAvailable != true {
                        Spacer(minLength: 8)
                        Button("Open Permissions", action: onOpenPermissions)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            if let operationStatus = visibleOperationStatus {
                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: operationStatus.symbolName)
                        .foregroundStyle(operationStatus.isSuccess ? Color.green : Color.orange)

                    Text(operationStatus.message)
                        .foregroundStyle(operationStatus.isSuccess ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            updateSpaceState()
            if !isPreRendering {
                spaceProvider?.refresh()
            }
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
        currentSpaces.compactMap { WallpaperSpaceTarget(space: $0) }
    }

    private var allSpaceTargets: [WallpaperSpaceTarget] {
        regularSpaces.compactMap { WallpaperSpaceTarget(space: $0) }
    }

    private var canSwitchOnActiveSpaces: Bool {
        spaceProvider?.isAvailable == true && !currentTargets.isEmpty
    }

    private var canSwitchSelection: Bool {
        model.selectedWallpaper != nil && !model.isLoading && !model.isSwitching
    }

    private var activeSpacesButtonTitle: LocalizedStringKey {
        currentTargets.isEmpty
            ? "Active spaces"
            : "Active spaces (\(currentTargets.count))"
    }

    private var allSpacesButtonTitle: LocalizedStringKey {
        guard spaceProvider?.isAvailable == true, !allSpaceTargets.isEmpty else {
            return "All spaces"
        }
        return "All spaces (\(allSpaceTargets.count))"
    }

    private var activeSpaceUnavailableTitle: LocalizedStringResource {
        if spaceProvider?.isAvailable == true {
            return "No active spaces are available"
        }
        return "Active-space switching is unavailable"
    }

    private var activeSpaceUnavailableMessage: LocalizedStringResource {
        if spaceProvider?.isAvailable == true {
            return "No regular Mission Control spaces were reported. All Spaces switching is still available."
        }
        return "Connect DesktopRenamer SpaceAPI in Permissions to switch only active spaces. All Spaces switching is still available."
    }

    private var visibleOperationStatus: WallpaperOperationStatus? {
        guard statusSelectionID == model.selectedWallpaperID else { return nil }
        return model.operationStatus
    }

    private func updateSpaceState() {
        snapshot = spaceProvider?.snapshot
        guard !currentTargets.isEmpty else { return }
        model.synchronizeCurrentWallpapers(for: currentTargets)
    }

    private func switchOnActiveSpaces() {
        guard let wallpaperID = model.selectedWallpaperID else { return }
        updateSpaceState()
        let targets = currentTargets
        guard model.applyWallpaper(id: wallpaperID, to: targets) else { return }
        automationCoordinator.recordManualWallpaperSwitch(of: wallpaperID, for: targets)
        statusSelectionID = wallpaperID
    }

    private func switchOnAllSpaces() {
        guard let wallpaperID = model.selectedWallpaperID else { return }

        if spaceProvider?.isAvailable == true {
            if allSpaceTargets.isEmpty {
                _ = model.applyWallpaper(id: wallpaperID, to: [])
            } else {
                let targets = allSpaceTargets
                model.synchronizeWallpaperIDs(for: targets)
                if model.applyWallpaper(id: wallpaperID, to: targets) {
                    automationCoordinator.recordManualWallpaperSwitch(
                        of: wallpaperID,
                        for: targets
                    )
                }
            }
        } else {
            _ = model.applyWallpaperEverywhere(id: wallpaperID)
        }
        statusSelectionID = wallpaperID
    }
}
