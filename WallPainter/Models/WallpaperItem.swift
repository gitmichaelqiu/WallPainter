import Foundation

struct WallpaperItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let thumbnailURL: URL?
    let videoURL: URL
    let preferredOrder: Int
}

extension WallpaperItem {
    static let preview = WallpaperItem(
        id: "preview-aerial",
        name: "Tahoe Evening",
        thumbnailURL: nil,
        videoURL: URL(fileURLWithPath: "/dev/null"),
        preferredOrder: 0
    )
}
