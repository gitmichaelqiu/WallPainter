import SwiftUI

struct WallpaperSwitchSection: View {
    @Bindable var model: WallpaperModel
    let automationCoordinator: WallpaperAutomationCoordinator
    let spaceProvider: (any SpaceAPIProviding)?
    let onOpenPermissions: () -> Void

    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @State private var snapshot: SpaceSnapshot?
    @State private var selectionSpaceID: String?
    @StateObject private var catalogScrollSession = CatalogScrollSession()
    @State private var statusSelectionID: String?

    private let wallpaperCatalogMaxHeight: CGFloat = 340

    var body: some View {
        SettingsSection(
            "Switch Once",
            helperText: "Changes the wallpaper without editing any rules. Each manual selection stays active until that space’s rule selects a different wallpaper. Choose Resume Rule from the menu bar to return to automation sooner."
        ) {
            SettingsRow("Currently active") {
                Text(currentFocusedWallpaperSummary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320, alignment: .trailing)
            }

            Divider()

            SettingsRow("Refresh catalog") {
                Button {
                    model.refresh()
                    updateSpaceState(selectCurrentWallpaper: true)
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
                    Button(focusedSpaceButtonTitle) {
                        switchOnFocusedSpace()
                    }
                    .accessibilityLabel("Switch wallpaper on focused space")
                    .disabled(!canSwitchOnFocusedSpace || !canSwitchSelection)

                    Button(allSpacesButtonTitle) {
                        switchOnAllSpaces()
                    }
                    .accessibilityLabel("Switch wallpaper on all spaces")
                    .disabled(!canSwitchSelection)
                }
            }

            if !canSwitchOnFocusedSpace {
                Divider()

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focusedSpaceUnavailableTitle)
                            .font(.subheadline)
                        Text(focusedSpaceUnavailableMessage)
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
            updateSpaceState(selectCurrentWallpaper: true)
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
        .onChange(of: model.items) { _, _ in
            updateSpaceState(selectCurrentWallpaper: true)
        }
    }

    private var regularSpaces: [SpaceDescriptor] {
        snapshot?.spaces.filter { !$0.isFullscreen } ?? []
    }

    private var focusedSpace: SpaceDescriptor? {
        guard spaceProvider?.isAvailable == true else { return nil }
        return snapshot?.focusedRegularSpace
    }

    private var focusedSpaceTarget: WallpaperSpaceTarget? {
        focusedSpace.flatMap { WallpaperSpaceTarget(space: $0) }
    }

    private var focusedTargets: [WallpaperSpaceTarget] {
        focusedSpaceTarget.map { [$0] } ?? []
    }

    private var allSpaceTargets: [WallpaperSpaceTarget] {
        regularSpaces.compactMap { WallpaperSpaceTarget(space: $0) }
    }

    private var canSwitchOnFocusedSpace: Bool {
        spaceProvider?.isAvailable == true && !focusedTargets.isEmpty
    }

    private var canSwitchSelection: Bool {
        model.selectedWallpaper != nil && !model.isLoading && !model.isSwitching
    }

    private var focusedSpaceButtonTitle: LocalizedStringKey {
        "Focused space"
    }

    private var allSpacesButtonTitle: LocalizedStringKey {
        guard spaceProvider?.isAvailable == true, !allSpaceTargets.isEmpty else {
            return "All spaces"
        }
        return "All spaces (\(allSpaceTargets.count))"
    }

    private var focusedSpaceUnavailableTitle: LocalizedStringResource {
        if spaceProvider?.isAvailable == true {
            return "No focused space is available"
        }
        return "Focused-space switching is unavailable"
    }

    private var focusedSpaceUnavailableMessage: LocalizedStringResource {
        if spaceProvider?.isAvailable == true {
            return "DesktopRenamer did not report the focused space. All Spaces switching is still available."
        }
        return "Connect DesktopRenamer SpaceAPI in Permissions to switch the focused space. All Spaces switching is still available."
    }

    private var visibleOperationStatus: WallpaperOperationStatus? {
        guard statusSelectionID == model.selectedWallpaperID else { return nil }
        return model.operationStatus
    }

    private var currentFocusedWallpaperSummary: String {
        guard let target = focusedSpaceTarget,
              let wallpaperID = model.currentWallpaperIDsBySpaceID[target.spaceID],
              let focusedSpace
        else { return String(localized: "Not detected") }

        return "\(model.wallpaperName(for: wallpaperID)) · \(focusedSpace.displayName)"
    }

    private func updateSpaceState(selectCurrentWallpaper: Bool = false) {
        snapshot = spaceProvider?.snapshot
        guard let target = focusedSpaceTarget else {
            selectionSpaceID = nil
            return
        }

        model.synchronizeWallpaperIDs(for: [target])
        guard model.currentWallpaperIDsBySpaceID[target.spaceID] != nil else {
            selectionSpaceID = nil
            return
        }

        if selectCurrentWallpaper || selectionSpaceID != target.spaceID {
            model.selectCurrentWallpaper(for: target)
        }
        selectionSpaceID = target.spaceID
    }

    private func switchOnFocusedSpace() {
        guard let wallpaperID = model.selectedWallpaperID else { return }
        updateSpaceState()
        let targets = focusedTargets
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
