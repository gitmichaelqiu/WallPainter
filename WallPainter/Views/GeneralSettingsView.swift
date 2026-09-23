import AppKit
import Combine
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: WallpaperModel
    let launchAtLoginManager: any LaunchAtLoginManaging
    let spaceProvider: (any SpaceAPIProviding)?

    @Environment(WallPainterPreferences.self) private var preferences
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @State private var launchAtLoginEnabled = false
    @State private var hasLoadedLaunchAtLogin = false
    @State private var snapshot: SpaceSnapshot?
    @StateObject private var catalogScrollSession = CatalogScrollSession()

    private let wallpaperCatalogMaxHeight: CGFloat = 420

    var body: some View {
        @Bindable var preferences = preferences

        SettingsContainer(.general) {
            VStack(alignment: .leading, spacing: 20) {
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

                SettingsSection("Current Wallpaper") {
                    SettingsRow("Current desktop wallpaper") {
                        Text(model.currentWallpaperName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220, alignment: .trailing)
                            .frame(minHeight: 24)
                    }
                }

                SettingsSection(
                    "Manual Wallpaper",
                    helperText: "Select a wallpaper and apply it once. This does not change Default or per-space rules; automation may later replace it."
                ) {
                    SettingsRow("Refresh catalog") {
                        Button {
                            model.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(minWidth: 20, minHeight: 20)
                        }
                        .accessibilityLabel("Refresh")
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

                    SettingsRow("Apply to current space(s)") {
                        Button {
                            applyToCurrentSpaces()
                        } label: {
                            if model.isSwitching {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Switching…")
                                }
                            } else {
                                Text("Apply")
                            }
                        }
                        .disabled(!canApplyToCurrentSpaces || model.isSwitching)
                    }

                    Divider()

                    SettingsRow("Apply Everywhere") {
                        Button("Apply") {
                            applyEverywhere()
                        }
                        .disabled(model.selectedWallpaper == nil || model.isSwitching)
                    }
                }

                SettingsSection("Wallpaper Protection") {
                    SettingsRow(
                        "Wallpaper protection",
                        helperText: "Keep backups of configured wallpapers and restore them if macOS removes them."
                    ) {
                        Toggle(
                            "",
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
                        if !preferences.wallpaperProtectionEnabled {
                            Text("Off")
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 24)
                        } else if model.assetProtectionStatus.isHealthy {
                            Text("\(model.assetProtectionStatus.protectedIDs.count) protected")
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 24)
                        } else {
                            HStack(spacing: 8) {
                                Text("Repair needed")
                                    .foregroundStyle(.orange)

                                Button("Repair") {
                                    model.reconcileProtectedAssets()
                                }
                            }
                            .frame(minHeight: 24)
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

private enum CatalogScrollTarget {
    case settings
    case catalog
}

private final class CatalogScrollSession: ObservableObject {
    @Published private(set) var target: CatalogScrollTarget?

    private var monitor: Any?
    private var resetWorkItem: DispatchWorkItem?
    private weak var regionView: CatalogScrollRegionView?

    func attach(regionView: CatalogScrollRegionView) {
        self.regionView = regionView
        startMonitoring()
    }

    func detach(regionView: CatalogScrollRegionView) {
        guard self.regionView === regionView else { return }
        self.regionView = nil
        stopMonitoring()
    }

    private func startMonitoring() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.receive(event)
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        resetWorkItem?.cancel()
        resetWorkItem = nil
        target = nil
    }

    private func receive(_ event: NSEvent) {
        guard let regionView else { return }

        if target == nil || event.phase.contains(.began) {
            target = regionView.contains(event.locationInWindow) ? .catalog : .settings
        }

        resetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.target = nil
        }
        resetWorkItem = workItem

        let delay: TimeInterval = event.phase.contains(.ended)
            && event.momentumPhase.isEmpty
            ? 0.05
            : 0.18
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

private struct CatalogScrollRegion: NSViewRepresentable {
    let session: CatalogScrollSession

    func makeNSView(context: Context) -> CatalogScrollRegionView {
        let view = CatalogScrollRegionView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: CatalogScrollRegionView, context: Context) {
        nsView.session = session
        if nsView.window != nil {
            session.attach(regionView: nsView)
        }
    }

    static func dismantleNSView(_ nsView: CatalogScrollRegionView, coordinator: ()) {
        nsView.session?.detach(regionView: nsView)
    }
}

private final class CatalogScrollRegionView: NSView {
    weak var session: CatalogScrollSession?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let session {
            session.attach(regionView: self)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let session {
            session.detach(regionView: self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func contains(_ pointInWindow: NSPoint) -> Bool {
        bounds.contains(convert(pointInWindow, from: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct WallpaperCatalogScrollView: View {
    let wallpapers: [WallpaperItem]
    @Binding var selection: String?
    let isLoading: Bool
    @ObservedObject var scrollSession: CatalogScrollSession
    let isPreRendering: Bool
    let maxHeight: CGFloat

    var body: some View {
        ScrollView(.vertical) {
            WallpaperCatalogContent(
                wallpapers: wallpapers,
                selection: $selection,
                isLoading: isLoading
            )
            .padding(10)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: maxHeight)
        .allowsHitTesting(scrollSession.target != .settings)
        .background {
            if !isPreRendering {
                CatalogScrollRegion(session: scrollSession)
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

struct WallpaperThumbnail: View {
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
