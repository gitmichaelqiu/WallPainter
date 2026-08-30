import Foundation

enum WallpaperStoreError: LocalizedError {
    case storeNotFound(URL)
    case invalidStore
    case noAerialChoices
    case reloadFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .storeNotFound:
            return "The macOS wallpaper store could not be found."
        case .invalidStore:
            return "The macOS wallpaper store has an unsupported format."
        case .noAerialChoices:
            return "No installed Apple Aerial wallpaper choices were found."
        case .reloadFailed(let status):
            return "WallpaperAgent could not be reloaded (exit status \(status))."
        }
    }
}

protocol WallpaperAgentReloading {
    func reload() throws
}

struct WallpaperAgentReloader: WallpaperAgentReloading {
    func reload() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        try process.run()
        process.waitUntilExit()

        // killall returns 1 when the agent was not running. launchd will start it again
        // when the wallpaper store is next needed, so that result is safe to ignore.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw WallpaperStoreError.reloadFailed(process.terminationStatus)
        }
    }
}

struct WallpaperStore {
    private static let aerialProvider = "com.apple.wallpaper.choice.aerials"

    private let indexURL: URL
    private let reloader: any WallpaperAgentReloading

    init(
        indexURL: URL = WallpaperStore.defaultIndexURL,
        reloader: any WallpaperAgentReloading = WallpaperAgentReloader()
    ) {
        self.indexURL = indexURL
        self.reloader = reloader
    }

    func currentAerialID() throws -> String? {
        let root = try readStore()
        return findAerialID(in: root)
    }

    func setAerialWallpaper(assetID: String) throws {
        let root = try readStore()
        let configuration = try makeConfiguration(assetID: assetID)
        let result = update(node: root, configuration: configuration)

        guard result.didChange else {
            throw WallpaperStoreError.noAerialChoices
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: result.node,
            format: .binary,
            options: 0
        )
        try data.write(to: indexURL, options: .atomic)
        try reloader.reload()
    }

    private static var defaultIndexURL: URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return supportDirectory
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true)
            .appendingPathComponent("Index.plist")
    }

    private func readStore() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw WallpaperStoreError.storeNotFound(indexURL)
        }

        let data = try Data(contentsOf: indexURL)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )

        guard let root = propertyList as? [String: Any] else {
            throw WallpaperStoreError.invalidStore
        }
        return root
    }

    private func makeConfiguration(assetID: String) throws -> Data {
        let configuration: [String: Any] = ["assetID": assetID]
        return try PropertyListSerialization.data(
            fromPropertyList: configuration,
            format: .binary,
            options: 0
        )
    }

    private func findAerialID(in node: Any) -> String? {
        if let dictionary = node as? [String: Any] {
            if dictionary["Provider"] as? String == Self.aerialProvider,
               let configuration = dictionary["Configuration"] as? Data {
                return decodeAssetID(from: configuration)
            }

            for child in dictionary.values {
                if let assetID = findAerialID(in: child) {
                    return assetID
                }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let assetID = findAerialID(in: child) {
                    return assetID
                }
            }
        }

        return nil
    }

    private func decodeAssetID(from configuration: Data) -> String? {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let propertyList = try? PropertyListSerialization.propertyList(
            from: configuration,
            options: [],
            format: &format
        ),
        let dictionary = propertyList as? [String: Any]
        else {
            return nil
        }
        return dictionary["assetID"] as? String
    }

    private func update(
        node: Any,
        configuration: Data
    ) -> (node: Any, didChange: Bool) {
        if var dictionary = node as? [String: Any] {
            var didChange = false

            if dictionary["Provider"] as? String == Self.aerialProvider {
                dictionary["Configuration"] = configuration
                didChange = true
            }

            for key in Array(dictionary.keys) where key != "Configuration" {
                guard let child = dictionary[key] else { continue }
                let childResult = update(node: child, configuration: configuration)
                guard childResult.didChange else { continue }
                dictionary[key] = childResult.node
                didChange = true
            }

            if didChange, dictionary["LastSet"] != nil {
                dictionary["LastSet"] = Date()
            }
            return (dictionary, didChange)
        }

        if let array = node as? [Any] {
            var didChange = false
            let updatedArray = array.map { child in
                let childResult = update(node: child, configuration: configuration)
                didChange = didChange || childResult.didChange
                return childResult.node
            }
            return (updatedArray, didChange)
        }

        return (node, false)
    }
}
