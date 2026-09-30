import AppKit
import AVFoundation
import AVKit
import Combine
import SwiftUI

enum CatalogScrollTarget {
    case settings
    case catalog
}

final class CatalogScrollSession: ObservableObject {
    @Published private(set) var target: CatalogScrollTarget?

    private var monitor: Any?
    private var resetWorkItem: DispatchWorkItem?
    private weak var regionView: CatalogScrollRegionView?

    fileprivate func attach(regionView: CatalogScrollRegionView) {
        self.regionView = regionView
        startMonitoring()
    }

    fileprivate func detach(regionView: CatalogScrollRegionView) {
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

struct WallpaperCatalogScrollView: View {
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
        .accessibilityValue(isSelected ? "Selected to switch" : "Not selected")
        .accessibilityHint("Select this wallpaper for a one-time switch")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
