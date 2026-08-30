import AppKit
import SwiftUI

struct SettingsWindowConfigurator: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> WindowSizingView {
        WindowSizingView(contentSize: contentSize)
    }

    func updateNSView(_ nsView: WindowSizingView, context: Context) {
        nsView.contentSize = contentSize
        nsView.scheduleWindowConfiguration()
    }

    final class WindowSizingView: NSView {
        var contentSize: CGSize
        private weak var configuredWindow: NSWindow?

        init(contentSize: CGSize) {
            self.contentSize = contentSize
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            contentSize = CGSize(width: 750, height: 550)
            super.init(coder: coder)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleWindowConfiguration()
        }

        func configureWindowIfNeeded() {
            guard let window, configuredWindow !== window else { return }
            guard !window.styleMask.contains(.fullScreen) else { return }

            if window.isZoomed {
                window.zoom(nil)
            }

            let size = NSSize(width: contentSize.width, height: contentSize.height)
            window.setContentSize(size)
            window.minSize = size
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.center()

            configuredWindow = window
        }

        func scheduleWindowConfiguration() {
            DispatchQueue.main.async { [weak self] in
                self?.configureWindowIfNeeded()
            }
        }
    }
}
