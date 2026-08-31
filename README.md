# WallPainter

WallPainter is a native macOS menu-bar utility for choosing Apple’s installed live Aerial wallpapers and applying them globally or per Mission Control space.

## Controls

WallPainter adds a `photo.tv` status bar item. Its `Switch` submenu lists every installed Aerial wallpaper. When DesktopRenamer SpaceAPI is available, the submenu marks a wallpaper as checked when every active regular space uses it and shows a mixed state when only some active spaces use it. Use `Settings…` to open the preferences window or `Quit WallPainter` to exit.

The settings window has four tabs:

- `General` shows the current wallpaper and active spaces, refreshes the installed Aerial catalog, applies a selected wallpaper to the current space(s) or everywhere, and controls the status bar item and launch-at-login behavior.
- `Spaces` groups regular Mission Control spaces by display. Each space inherits the `All Spaces` rule by default, or can override it with a fixed wallpaper or a Light/Dark appearance rule. Full-screen app spaces are omitted because macOS recreates them.
- `Automation` defines the `All Spaces` rule as either one fixed wallpaper or a Light/Dark pair. Automatic switching stays disabled until the default rule is valid. With SpaceAPI available, changes are applied independently to every known regular space; unavailable or invalid per-space overrides are left unchanged while other valid spaces continue.
- `About` contains WallPainter metadata, project links, acknowledgements, and links to the other apps in this suite, including DesktopRenamer.

WallPainter stores its selections, the All Spaces rule, and per-space overrides in namespaced user defaults. The default state is automation off, no mappings, a visible status item, and launch at login off. Existing Light/Dark mappings are migrated into the All Spaces rule. If a mapped wallpaper is removed from the local Aerial catalog, WallPainter disables automation while retaining the saved IDs so the mapping can be repaired after the wallpaper is installed again.

Space-aware automation uses DesktopRenamer’s structured SpaceAPI. If the API is unavailable, automatic switching pauses rather than applying a global wallpaper silently. The explicit `Apply Everywhere` action in `General` remains available as a manual fallback. Manual selections from the status-bar menu apply only to the currently active regular spaces and do not rewrite saved automation rules.

## Running

Open `WallPainter.xcodeproj` in Xcode and run the `WallPainter` scheme on macOS. WallPainter starts as a menu-bar app. Launching it again while it is already running opens and focuses the settings window.

WallPainter currently requires the macOS WallpaperAgent store used by recent macOS releases. The app target intentionally disables App Sandbox because applying an Aerial requires writing the per-user wallpaper store and asking WallpaperAgent to reload.

## Repository conventions

See `CONTRIBUTING.md` for commit-message and documentation standards.
