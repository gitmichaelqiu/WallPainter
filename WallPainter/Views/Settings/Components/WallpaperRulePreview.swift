import SwiftUI

struct WallpaperRulePreview: View {
    let rule: WallpaperRule
    let wallpapers: [WallpaperItem]
    let title: LocalizedStringResource

    private var fixedWallpaper: WallpaperItem? {
        wallpaper(withID: rule.fixedWallpaperID)
    }

    private var lightWallpaper: WallpaperItem? {
        wallpaper(withID: rule.lightWallpaperID)
    }

    private var darkWallpaper: WallpaperItem? {
        wallpaper(withID: rule.darkWallpaperID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch rule.mode {
            case .fixed:
                SpaceWallpaperPreviewCard(
                    wallpaper: fixedWallpaper,
                    label: "Fixed"
                )
            case .appearance:
                HStack(spacing: 12) {
                    SpaceWallpaperPreviewCard(
                        wallpaper: lightWallpaper,
                        label: "Light"
                    )

                    SpaceWallpaperPreviewCard(
                        wallpaper: darkWallpaper,
                        label: "Dark"
                    )
                }
            case .manual:
                Text("No automatic wallpaper changes")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(10)
    }

    private func wallpaper(withID id: String?) -> WallpaperItem? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }
}

private struct SpaceWallpaperPreviewCard: View {
    let wallpaper: WallpaperItem?
    let label: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let wallpaper {
                WallpaperThumbnail(url: wallpaper.thumbnailURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipShape(.rect(cornerRadius: 8))

                HStack(spacing: 8) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(wallpaper.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Wallpaper unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
