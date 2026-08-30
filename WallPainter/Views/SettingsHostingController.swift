import AppKit
import SwiftUI

@MainActor
final class SettingsHostingController: NSHostingController<AnyView> {
    init(
        model: WallpaperModel,
        preferences: WallPainterPreferences,
        initialTab: SettingsTab? = nil
    ) {
        let rootView = SettingsView(
            model: model,
            launchAtLoginManager: LaunchAtLoginManager(),
            initialTab: initialTab
        )
            .environment(preferences)
        super.init(rootView: AnyView(rootView))
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 750, height: 550)
    }
}
