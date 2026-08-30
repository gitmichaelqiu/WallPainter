import Foundation

private struct AerialManifest: Decodable {
    let assets: [AerialAsset]
}

private struct AerialAsset: Decodable {
    let id: String
    let accessibilityLabel: String?
    let preferredOrder: Int?
    let shotID: String?
}

struct SystemWallpaperCatalog {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func installedAerials() throws -> [WallpaperItem] {
        let supportDirectory = applicationSupportDirectory
        let aerialDirectory = supportDirectory
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("aerials", isDirectory: true)
        let videoDirectory = aerialDirectory.appendingPathComponent("videos", isDirectory: true)
        let thumbnailDirectory = aerialDirectory.appendingPathComponent("thumbnails", isDirectory: true)

        guard fileManager.fileExists(atPath: videoDirectory.path) else {
            return []
        }

        let manifestEntries = loadManifestEntries(from: [
            aerialDirectory
                .appendingPathComponent("manifest", isDirectory: true)
                .appendingPathComponent("entries.json"),
            URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources/entries.json")
        ])

        let localVideoURLs = try fileManager.contentsOfDirectory(
            at: videoDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.caseInsensitiveCompare("mov") == .orderedSame }

        let entriesByID = Dictionary(uniqueKeysWithValues: manifestEntries.map { ($0.id, $0) })
        let localIDs = Set(localVideoURLs.map { $0.deletingPathExtension().lastPathComponent })
        let allIDs = localIDs.union(entriesByID.keys)

        return allIDs.compactMap { id in
            let videoURL = videoDirectory.appendingPathComponent("\(id).mov")
            guard fileManager.fileExists(atPath: videoURL.path) else {
                return nil
            }

            let entry = entriesByID[id]
            let thumbnailURL = thumbnailDirectory.appendingPathComponent("\(id).png")
            let hasThumbnail = fileManager.fileExists(atPath: thumbnailURL.path)

            return WallpaperItem(
                id: id,
                name: displayName(for: entry, id: id),
                thumbnailURL: hasThumbnail ? thumbnailURL : nil,
                videoURL: videoURL,
                preferredOrder: entry?.preferredOrder ?? Int.max
            )
        }
        .sorted {
            if $0.preferredOrder == $1.preferredOrder {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.preferredOrder < $1.preferredOrder
        }
    }

    private var applicationSupportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private func loadManifestEntries(from urls: [URL]) -> [AerialAsset] {
        var entriesByID: [String: AerialAsset] = [:]

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(AerialManifest.self, from: data)
            else {
                continue
            }

            for entry in manifest.assets {
                guard !entry.id.isEmpty else { continue }
                if let existing = entriesByID[entry.id] {
                    entriesByID[entry.id] = merge(existing: existing, incoming: entry)
                } else {
                    entriesByID[entry.id] = entry
                }
            }
        }

        return Array(entriesByID.values)
    }

    private func merge(existing: AerialAsset, incoming: AerialAsset) -> AerialAsset {
        let incomingName = meaningfulName(incoming.accessibilityLabel)
        let existingName = meaningfulName(existing.accessibilityLabel)

        return AerialAsset(
            id: incoming.id,
            accessibilityLabel: incomingName ?? existingName ?? incoming.accessibilityLabel ?? existing.accessibilityLabel,
            preferredOrder: incoming.preferredOrder ?? existing.preferredOrder,
            shotID: incoming.shotID ?? existing.shotID
        )
    }

    private func displayName(for entry: AerialAsset?, id: String) -> String {
        if let name = entry.flatMap({ meaningfulName($0.accessibilityLabel) }) {
            return name
        }

        let shotID = entry?.shotID?.uppercased() ?? ""
        if shotID.contains("GG_A_SUNSET") {
            return "Golden Gate Sunset"
        }
        if shotID.contains("GG_A_EVENING") {
            return "Golden Gate Evening"
        }
        if shotID.contains("GG_A_DAY") {
            return "Golden Gate Day"
        }
        if shotID.contains("GG_A_NIGHT") {
            return "Golden Gate Night"
        }
        if shotID.contains("GG_LM") {
            return "Golden Gate Day"
        }
        if shotID.contains("GG_DM") {
            return "Golden Gate Night"
        }

        return "Apple Aerial \(id.prefix(8))"
    }

    private func meaningfulName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              name.caseInsensitiveCompare("macOS") != .orderedSame
        else {
            return nil
        }
        return name
    }
}
