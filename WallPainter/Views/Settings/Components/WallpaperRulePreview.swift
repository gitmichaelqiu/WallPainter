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
                .font(.body)

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
            case .timeSchedule:
                if rule.timePeriods.isEmpty {
                    Text("No time periods configured")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rule.timePeriods) { period in
                            let periodWallpaper = wallpaper(withID: period.wallpaperID)
                            let isOvernight = period.startMinute > period.endMinute
                            let wallpaperName = periodWallpaper?.name
                                ?? (period.wallpaperID == nil ? "No wallpaper selected" : "Wallpaper unavailable")

                            SettingsValueRow(horizontalPadding: 0) {
                                HStack(spacing: 16) {
                                    HStack(spacing: 4) {
                                        Text(period.formattedTimeRange)
                                        if isOvernight {
                                            Text("Next day")
                                                .font(.caption)
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 220, alignment: .leading)

                                    Text(wallpaperName)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } trailing: {
                                ScheduledWallpaperThumbnail(
                                    wallpaper: periodWallpaper,
                                    isUnavailable: period.wallpaperID != nil && periodWallpaper == nil
                                )
                            }
                        }
                    }
                }
            case .manual:
                Text("No automatic wallpaper changes")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func wallpaper(withID id: String?) -> WallpaperItem? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }
}

struct ScheduledWallpaperThumbnail: View {
    private static let width: CGFloat = 144
    private static let height: CGFloat = 81

    let wallpaper: WallpaperItem?
    let isUnavailable: Bool

    var body: some View {
        Group {
            if let wallpaper {
                WallpaperThumbnail(url: wallpaper.thumbnailURL)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary.opacity(0.35))
                    Image(systemName: isUnavailable ? "exclamationmark.triangle" : "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        if let wallpaper {
            Text(wallpaper.name)
        } else if isUnavailable {
            Text("Wallpaper unavailable")
        } else {
            Text("No wallpaper selected")
        }
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
