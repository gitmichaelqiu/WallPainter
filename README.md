# WallPainter

WallPainter is a native macOS menu-bar utility for choosing Apple’s installed live Aerial wallpapers and pairing them with the system appearance.

## Controls

WallPainter adds a `photo.tv` status bar item. Its `Switch` submenu lists every installed Aerial wallpaper and checks the wallpaper currently reported by macOS. Use `Settings…` to open the preferences window or `Quit WallPainter` to exit.

The settings window has three tabs:

- `General` shows the current wallpaper, refreshes the installed Aerial catalog, applies a selected wallpaper, and controls the status bar item and launch-at-login behavior.
- `Automation` maps one installed wallpaper to Light appearance and one to Dark appearance. Automatic switching stays disabled until both mappings are installed. Automation evaluates once at launch and whenever the system appearance changes.
- `About` contains WallPainter metadata, project links, acknowledgements, and links to the other apps in this suite, including DesktopRenamer.

WallPainter stores its selections and automation mappings in namespaced user defaults. The default state is automation off, no mappings, a visible status item, and launch at login off. If a mapped wallpaper is removed from the local Aerial catalog, WallPainter turns automation off while retaining the saved IDs so the mapping can be repaired after the wallpaper is installed again.

## Running

Open `WallPainter.xcodeproj` in Xcode and run the `WallPainter` scheme on macOS. WallPainter starts as a menu-bar app. Launching it again while it is already running opens and focuses the settings window.

WallPainter currently requires the macOS WallpaperAgent store used by recent macOS releases. The app target intentionally disables App Sandbox because applying an Aerial requires writing the per-user wallpaper store and asking WallpaperAgent to reload.

## Repository conventions

See `CONTRIBUTING.md` for commit-message and documentation standards.
