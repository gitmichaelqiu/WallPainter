import Foundation

private struct AerialManifest: Decodable {
    let assets: [AerialAsset]
}

protocol WallpaperNameLocalizing {
    func localizedString(forKey key: String) -> String?
}

struct BundleWallpaperNameLocalizer: WallpaperNameLocalizing {
    let bundle: Bundle?

    static let system = BundleWallpaperNameLocalizer(
        bundle: Bundle(
            path: "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources/TVIdleScreenStrings.bundle"
        )
    )

    func localizedString(forKey key: String) -> String? {
        guard let bundle else { return nil }

        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }
}

private struct AerialAsset: Decodable {
    let id: String
    let accessibilityLabel: String?
    let preferredOrder: Int?
    let shotID: String?
    let localizedNameKey: String?
    let variant: AerialVariant?
}

private struct AerialVariant: Decodable {
    let appearance: String?
    let orientation: String?
}

struct SystemWallpaperCatalog: WallpaperCatalogProviding {
    private let fileManager: FileManager
    private let supportDirectory: URL?
    private let nameLocalizer: any WallpaperNameLocalizing

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        nameLocalizer: any WallpaperNameLocalizing = BundleWallpaperNameLocalizer.system
    ) {
        self.fileManager = fileManager
        supportDirectory = applicationSupportDirectory
        self.nameLocalizer = nameLocalizer
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

        let items: [WallpaperItem] = allIDs.compactMap { id -> WallpaperItem? in
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

        return disambiguated(items)
    }

    private var applicationSupportDirectory: URL {
        if let supportDirectory {
            return supportDirectory
        }

        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
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
            shotID: incoming.shotID ?? existing.shotID,
            localizedNameKey: incoming.localizedNameKey ?? existing.localizedNameKey,
            variant: incoming.variant ?? existing.variant
        )
    }

    private func displayName(for entry: AerialAsset?, id: String) -> String {
        if let entry,
           let dynamicAppearance = dynamicAppearance(for: entry) {
            let appearance = localizedName(for: entry.localizedNameKey)
                ?? dynamicAppearance
            let orientation = entry.variant?.orientation.map { $0.capitalized }
            let baseName = ["macOS", appearance].compactMap { $0 }.joined(separator: " ")

            if let orientation {
                return "\(baseName) (\(orientation))"
            }
            return baseName
        }

        if let name = entry.flatMap({ localizedName(for: $0.localizedNameKey) }) {
            return name
        }

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

        return "Apple Aerial \(id.prefix(8))"
    }

    private func dynamicAppearance(for entry: AerialAsset) -> String? {
        switch entry.localizedNameKey {
        case "DYNAMIC_LIGHT_KEY":
            return "Light"
        case "DYNAMIC_DARK_KEY":
            return "Dark"
        default:
            break
        }

        let shotID = entry.shotID?.uppercased() ?? ""
        if shotID.contains("GG_LM") {
            return "Light"
        }
        if shotID.contains("GG_DM") {
            return "Dark"
        }
        return nil
    }

    private func localizedName(for key: String?) -> String? {
        guard let key,
              let name = nameLocalizer.localizedString(forKey: key)
        else {
            return nil
        }
        return meaningfulName(name)
    }

    private func disambiguated(_ items: [WallpaperItem]) -> [WallpaperItem] {
        let counts = Dictionary(grouping: items, by: \.name)
            .mapValues(\.count)
        var occurrences = [String: Int]()

        return items.map { item in
            guard counts[item.name, default: 0] > 1 else {
                return item
            }

            let occurrence = occurrences[item.name, default: 0] + 1
            occurrences[item.name] = occurrence

            return WallpaperItem(
                id: item.id,
                name: "\(item.name) (\(occurrence))",
                thumbnailURL: item.thumbnailURL,
                videoURL: item.videoURL,
                preferredOrder: item.preferredOrder
            )
        }
    }

    private func meaningfulName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              name.caseInsensitiveCompare("macOS") != .orderedSame,
              !(name.contains("_") && name == name.uppercased())
        else {
            return nil
        }
        return name
    }
}
