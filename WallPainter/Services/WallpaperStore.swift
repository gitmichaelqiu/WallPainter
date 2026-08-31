import Foundation

enum WallpaperStoreError: LocalizedError {
    case storeNotFound(URL)
    case invalidStore
    case noAerialChoices
    case spaceNotFound(String)
    case reloadFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .storeNotFound:
            return "The macOS wallpaper store could not be found."
        case .invalidStore:
            return "The macOS wallpaper store has an unsupported format."
        case .noAerialChoices:
            return "No installed Apple Aerial wallpaper choices were found."
        case .spaceNotFound(let spaceID):
            return "The wallpaper store does not contain space \(spaceID)."
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

struct WallpaperStore: WallpaperStoring {
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

    func currentAerialIDs(for targets: [WallpaperSpaceTarget]) throws -> [String: String] {
        guard !targets.isEmpty else { return [:] }

        let root = try readStore()
        let spaces = root["Spaces"] as? [String: Any] ?? [:]
        let displays = root["Displays"] as? [String: Any] ?? [:]
        var result: [String: String] = [:]

        for target in uniqueTargets(targets) {
            if let space = spaces[target.spaceID],
               let wallpaperID = findAerialID(in: space, forDisplayID: target.displayID) {
                result[target.spaceID] = wallpaperID
                continue
            }

            if let display = displays[target.displayID],
               let wallpaperID = findAerialID(in: display) {
                result[target.spaceID] = wallpaperID
            }
        }

        return result
    }

    func setAerialWallpaper(assetID: String) throws {
        let root = try readStore()
        let configuration = try makeConfiguration(assetID: assetID)
        let result = updateExistingAerial(node: root, configuration: configuration)

        guard result.didChange else {
            throw WallpaperStoreError.noAerialChoices
        }

        try writeAndReload(result.node)
    }

    func setAerialWallpapers(
        _ wallpaperIDsBySpaceID: [String: String],
        for targets: [WallpaperSpaceTarget]
    ) throws {
        let targets = uniqueTargets(targets)
        guard !targets.isEmpty else { return }

        let root = try readStore()
        var configurations: [String: Data] = [:]
        for (spaceID, wallpaperID) in wallpaperIDsBySpaceID {
            configurations[spaceID] = try makeConfiguration(assetID: wallpaperID)
        }
        let spaces = root["Spaces"] as? [String: Any] ?? [:]
        var updatedRoot = root
        var updatedSpaces = spaces
        var didChange = false

        for target in targets {
            guard let configuration = configurations[target.spaceID] else {
                throw WallpaperStoreError.noAerialChoices
            }
            guard let space = spaces[target.spaceID] else {
                throw WallpaperStoreError.spaceNotFound(target.spaceID)
            }

            let spaceResult = updateTarget(node: space, configuration: configuration)
            guard spaceResult.hasWritableChoice else {
                throw WallpaperStoreError.noAerialChoices
            }
            updatedSpaces[target.spaceID] = spaceResult.node
            didChange = didChange || spaceResult.didChange

            if var rootDisplays = updatedRoot["Displays"] as? [String: Any],
               let display = rootDisplays[target.displayID] {
                let displayResult = updateTarget(node: display, configuration: configuration)
                if displayResult.hasWritableChoice {
                    rootDisplays[target.displayID] = displayResult.node
                    didChange = didChange || displayResult.didChange
                    updatedRoot["Displays"] = rootDisplays
                }
            }
        }

        updatedRoot["Spaces"] = updatedSpaces
        guard didChange else { return }
        try writeAndReload(updatedRoot)
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

    private func writeAndReload(_ root: Any) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try data.write(to: indexURL, options: .atomic)
        try reloader.reload()
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

    private func findAerialID(in node: Any, forDisplayID displayID: String) -> String? {
        guard let dictionary = node as? [String: Any] else {
            return findAerialID(in: node)
        }

        if let displays = dictionary["Displays"] as? [String: Any],
           let display = displays[displayID],
           let wallpaperID = findAerialID(in: display) {
            return wallpaperID
        }

        if let defaultNode = dictionary["Default"],
           let wallpaperID = findAerialID(in: defaultNode) {
            return wallpaperID
        }

        return findAerialID(in: node)
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

    private func updateExistingAerial(
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
                let childResult = updateExistingAerial(node: child, configuration: configuration)
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
                let childResult = updateExistingAerial(node: child, configuration: configuration)
                didChange = didChange || childResult.didChange
                return childResult.node
            }
            return (updatedArray, didChange)
        }

        return (node, false)
    }

    private func updateTarget(
        node: Any,
        configuration: Data
    ) -> (node: Any, didChange: Bool, hasWritableChoice: Bool) {
        if var dictionary = node as? [String: Any] {
            var didChange = false
            var hasWritableChoice = false

            if let choices = dictionary["Choices"] as? [Any] {
                let choicesResult = updateChoices(choices, configuration: configuration)
                dictionary["Choices"] = choicesResult.choices
                didChange = choicesResult.didChange
                hasWritableChoice = choicesResult.hasWritableChoice
            }

            for key in Array(dictionary.keys) where key != "Configuration" && key != "Choices" {
                guard let child = dictionary[key] else { continue }
                let childResult = updateTarget(node: child, configuration: configuration)
                guard childResult.hasWritableChoice else { continue }
                dictionary[key] = childResult.node
                didChange = didChange || childResult.didChange
                hasWritableChoice = true
            }

            if didChange, dictionary["LastSet"] != nil {
                dictionary["LastSet"] = Date()
            }
            return (dictionary, didChange, hasWritableChoice)
        }

        return (node, false, false)
    }

    private func updateChoices(
        _ choices: [Any],
        configuration: Data
    ) -> (choices: [Any], didChange: Bool, hasWritableChoice: Bool) {
        var updatedChoices = choices
        var didChange = false
        var hasAerialChoice = false

        for index in updatedChoices.indices {
            guard var choice = updatedChoices[index] as? [String: Any],
                  choice["Provider"] as? String == Self.aerialProvider
            else { continue }

            hasAerialChoice = true
            if (choice["Configuration"] as? Data) != configuration {
                choice["Configuration"] = configuration
                updatedChoices[index] = choice
                didChange = true
            }
        }

        if !hasAerialChoice,
           var firstChoice = updatedChoices.first as? [String: Any] {
            firstChoice["Provider"] = Self.aerialProvider
            firstChoice["Configuration"] = configuration
            updatedChoices[updatedChoices.startIndex] = firstChoice
            didChange = true
            hasAerialChoice = true
        }

        return (updatedChoices, didChange, hasAerialChoice)
    }

    private func uniqueTargets(_ targets: [WallpaperSpaceTarget]) -> [WallpaperSpaceTarget] {
        var seenSpaceIDs = Set<String>()
        return targets.filter { target in
            guard !target.spaceID.isEmpty, seenSpaceIDs.insert(target.spaceID).inserted else {
                return false
            }
            return true
        }
    }
}
