# WallPainter

WallPainter is a native macOS utility for choosing Apple’s installed live Aerial wallpapers. This first slice is deliberately a manual debug interface for validating wallpaper selection and switching.

## Current debug slice

- Reads installed Aerial names, thumbnails, and videos from macOS’s local wallpaper catalog.
- Lets you select an installed Aerial and apply it to the wallpaper choices stored for the configured spaces and displays.
- Shows the detected current Aerial and reports switch errors in the UI.
- Does not yet detect the system appearance or automatically pair light and dark wallpapers.

## Running

Open `WallPainter.xcodeproj` in Xcode and run the `WallPainter` scheme on macOS. The app opens the same settings-style interface as its main window; the standard Settings command is also available from the app menu.

WallPainter currently requires the macOS WallpaperAgent store used by recent macOS releases. The app target intentionally disables App Sandbox because applying an Aerial requires writing the per-user wallpaper store and asking WallpaperAgent to reload.

## Repository conventions

See `CONTRIBUTING.md` for commit-message and documentation standards.
