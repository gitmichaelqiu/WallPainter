import AppKit
import Foundation
import Observation

private struct LegacySpaceSnapshotResponse: Sendable {
    let requestID: String
    let succeeded: Bool
    let result: String?
}

private struct LegacySpaceMappingValidation: Sendable {
    let expectedRevision: UInt64
    let spaces: [SpaceDescriptor]
}

struct SpaceDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let displayID: String
    let displayName: String
    let number: Int
    let isFullscreen: Bool
    /// Current macOS ID from the legacy SpaceAPI snapshot; never a persisted key.
    let managedSpaceID: String?

    init(
        id: String,
        name: String,
        displayID: String,
        displayName: String,
        number: Int,
        isFullscreen: Bool,
        managedSpaceID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayID = displayID
        self.displayName = displayName
        self.number = number
        self.isFullscreen = isFullscreen
        self.managedSpaceID = managedSpaceID
    }
}

struct SpaceSnapshot: Codable, Equatable, Sendable {
    let revision: UInt64
    let currentSpaceIDs: [String]
    let currentSpaceID: String?
    let currentDisplayID: String?
    let spaces: [SpaceDescriptor]

    init(
        revision: UInt64,
        currentSpaceIDs: [String],
        currentSpaceID: String? = nil,
        currentDisplayID: String? = nil,
        spaces: [SpaceDescriptor]
    ) {
        self.revision = revision
        self.currentSpaceIDs = currentSpaceIDs
        self.currentSpaceID = currentSpaceID
        self.currentDisplayID = currentDisplayID
        self.spaces = spaces
    }
}

private struct SpacePositionKey: Hashable {
    let displayID: String
    let number: Int
    let name: String
    let isFullscreen: Bool

    init(_ space: SpaceDescriptor) {
        displayID = space.displayID
        number = space.number
        name = space.name
        isFullscreen = space.isFullscreen
    }
}

extension SpaceSnapshot {
    /// Joins a legacy snapshot only when it describes the same complete layout.
    /// Legacy SpaceAPI has no revision, so callers must also verify this against
    /// a fresh structured snapshot before using the resulting macOS IDs.
    func attachingManagedSpaceIDs(from legacySpaces: [SpaceDescriptor]) -> SpaceSnapshot? {
        let structuredKeys = spaces.map(SpacePositionKey.init)
        let legacyKeys = legacySpaces.map(SpacePositionKey.init)
        let structuredCounts = Dictionary(grouping: structuredKeys, by: { $0 })
            .mapValues(\.count)
        let legacyCounts = Dictionary(grouping: legacyKeys, by: { $0 })
            .mapValues(\.count)

        guard !spaces.isEmpty,
              structuredCounts == legacyCounts,
              legacyCounts.values.allSatisfy({ $0 == 1 })
        else { return nil }

        let managedIDsByPosition = Dictionary(uniqueKeysWithValues: legacySpaces.map {
            (SpacePositionKey($0), $0.managedSpaceID ?? $0.id)
        })
        let mappedSpaces = spaces.map { space in
            SpaceDescriptor(
                id: space.id,
                name: space.name,
                displayID: space.displayID,
                displayName: space.displayName,
                number: space.number,
                isFullscreen: space.isFullscreen,
                managedSpaceID: managedIDsByPosition[SpacePositionKey(space)]
            )
        }

        return SpaceSnapshot(
            revision: revision,
            currentSpaceIDs: currentSpaceIDs,
            currentSpaceID: currentSpaceID,
            currentDisplayID: currentDisplayID,
            spaces: mappedSpaces
        )
    }
}

extension SpaceSnapshot {
    var focusedRegularSpace: SpaceDescriptor? {
        let spacesByID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })

        if let currentSpaceID, !currentSpaceID.isEmpty {
            guard currentSpaceIDs.contains(currentSpaceID),
                  let space = spacesByID[currentSpaceID],
                  !space.isFullscreen
            else { return nil }
            return space
        }

        if let currentDisplayID, !currentDisplayID.isEmpty {
            let matches = currentSpaceIDs.compactMap { spacesByID[$0] }
                .filter { $0.displayID == currentDisplayID && !$0.isFullscreen }
            guard matches.count == 1 else { return nil }
            return matches[0]
        }

        guard currentSpaceIDs.count == 1,
              let spaceID = currentSpaceIDs.first,
              let space = spacesByID[spaceID],
              !space.isFullscreen
        else { return nil }
        return space
    }

    var focusedRegularSpaceTarget: WallpaperSpaceTarget? {
        guard let space = focusedRegularSpace else { return nil }
        return WallpaperSpaceTarget(space: space)
    }
}

struct SpaceAPIInfo: Codable, Equatable, Sendable {
    let contractVersion: String
    let jsonRPCVersion: String
    let supportedMethods: [String]
}

enum SpaceAPIAvailability: Equatable, Sendable {
    case available
    case disabled
    case unavailable
}

struct SpaceAPIError: LocalizedError, Equatable, Sendable {
    let code: Int
    let message: String

    var errorDescription: String? { message }
}

enum SpaceAPICodecError: LocalizedError, Equatable {
    case invalidPayload
    case invalidResponse
    case unsupportedAPI
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "DesktopRenamer returned invalid SpaceAPI JSON."
        case .invalidResponse:
            return "DesktopRenamer returned an invalid SpaceAPI response."
        case .unsupportedAPI:
            return "The installed DesktopRenamer does not support structured SpaceAPI snapshots."
        case .missingField(let field):
            return "The SpaceAPI response is missing \(field)."
        }
    }
}

enum SpaceAPIEventDisposition: Equatable {
    case apply
    case stale
    case gap
}

struct SpaceAPIRevisionTracker: Equatable, Sendable {
    private(set) var revision: UInt64?

    mutating func acceptSnapshot(revision: UInt64) -> Bool {
        guard self.revision.map({ revision > $0 }) ?? true else { return false }
        self.revision = revision
        return true
    }

    mutating func acceptVerifiedSnapshot(revision: UInt64) -> Bool {
        guard self.revision.map({ revision >= $0 }) ?? true else { return false }
        self.revision = revision
        return true
    }

    mutating func evaluateEvent(revision: UInt64) -> SpaceAPIEventDisposition {
        guard let currentRevision = self.revision else {
            self.revision = revision
            return .apply
        }
        guard revision > currentRevision else { return .stale }
        guard revision == currentRevision + 1 else { return .gap }
        self.revision = revision
        return .apply
    }

    mutating func reset() {
        revision = nil
    }
}

@MainActor
protocol SpaceAPIProviding {
    var snapshot: SpaceSnapshot? { get }
    var isAvailable: Bool { get }
    func start()
    func stop()
    func refresh()
}

extension Notification.Name {
    static let wallPainterSpaceSnapshotDidChange = Notification.Name(
        "WallPainter.spaceSnapshotDidChange"
    )
    static let wallPainterSpaceAvailabilityDidChange = Notification.Name(
        "WallPainter.spaceAvailabilityDidChange"
    )
}

@MainActor
@Observable
final class SpaceAPIClient: SpaceAPIProviding {
    static let requestNotification = Notification.Name(
        "com.michaelqiu.DesktopRenamer.RPCRequest"
    )
    static let responseNotification = Notification.Name(
        "com.michaelqiu.DesktopRenamer.RPCResponse"
    )
    static let eventNotification = Notification.Name(
        "com.michaelqiu.DesktopRenamer.RPCEvent"
    )
    static let apiStateNotification = Notification.Name(
        "com.michaelqiu.DesktopRenamer.ReturnAPIState"
    )
    static let legacyRequestNotification = Notification.Name(
        "dev.mqiu.DesktopRenamer.PerformCommand"
    )
    private static let legacyResponseNotifications = [
        Notification.Name("dev.mqiu.DesktopRenamer.CommandResult"),
        Notification.Name("com.michaelqiu.DesktopRenamer.CommandResult")
    ]
    static let desktopRenamerBundleIdentifiers = [
        "dev.mqiu.DesktopRenamer",
        "com.michaelqiu.DesktopRenamer"
    ]
    static let desktopRenamerDownloadURL = URL(
        string: "https://github.com/gitmichaelqiu/DesktopRenamer/releases/latest"
    )!

    private(set) var snapshot: SpaceSnapshot?
    private(set) var isAvailable = false
    private(set) var apiAvailability: SpaceAPIAvailability = .unavailable
    private(set) var negotiatedAPIInfo: SpaceAPIInfo?

    @ObservationIgnored private let center: DistributedNotificationCenter
    @ObservationIgnored private let disconnectNotifications: SpaceAPIDisconnectNotificationManager
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var responseObserver: NSObjectProtocol?
    @ObservationIgnored private var legacyResponseObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var eventObserver: NSObjectProtocol?
    @ObservationIgnored private var apiStateObserver: NSObjectProtocol?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingMethods: [String: String] = [:]
    @ObservationIgnored private var pendingTimeouts: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private var revisionTracker = SpaceAPIRevisionTracker()
    @ObservationIgnored private var isWaitingForSnapshot = false
    @ObservationIgnored private var desktopRenamerProcessIdentifier: pid_t?
    @ObservationIgnored private var legacySnapshotRequestID: String?
    @ObservationIgnored private var legacySnapshotRevision: UInt64?
    @ObservationIgnored private var legacySnapshotTimeout: DispatchWorkItem?
    @ObservationIgnored private var legacyMappingVerificationRequestID: String?
    @ObservationIgnored private var pendingLegacyMappingValidation: LegacySpaceMappingValidation?
    @ObservationIgnored private var legacyMappingRetryWorkItem: DispatchWorkItem?
    @ObservationIgnored private var legacyMappingRetryCount = 0

    init(
        center: DistributedNotificationCenter = .default(),
        disconnectNotifications: SpaceAPIDisconnectNotificationManager
    ) {
        self.center = center
        self.disconnectNotifications = disconnectNotifications
    }

    var disconnectNotificationManager: SpaceAPIDisconnectNotificationManager {
        disconnectNotifications
    }

    func start() {
        stop()
        isRunning = true
        desktopRenamerProcessIdentifier = currentDesktopRenamerProcessIdentifier
        isWaitingForSnapshot = true
        installObservers()
        requestAPIInfo()
    }

    func stop() {
        isRunning = false
        removeObservers()
        for timeout in pendingTimeouts.values {
            timeout.cancel()
        }
        pendingTimeouts.removeAll()
        pendingMethods.removeAll()
        legacySnapshotTimeout?.cancel()
        legacySnapshotTimeout = nil
        legacySnapshotRequestID = nil
        legacySnapshotRevision = nil
        cancelLegacyMappingVerification()
        cancelLegacyMappingRetry()
        revisionTracker.reset()
        isWaitingForSnapshot = false
        desktopRenamerProcessIdentifier = nil
        negotiatedAPIInfo = nil
        snapshot = nil
        markUnavailable()
    }

    func refresh() {
        guard isRunning else { return }
        let processChanged = synchronizeDesktopRenamerProcess()
        if processChanged, desktopRenamerProcessIdentifier == nil {
            markUnavailable()
            return
        }
        requestAPIInfo()

        if processChanged {
            // The app may post its launch notification before SpaceAPI installs
            // its request listener. Retry the probe while it finishes starting.
            for delay in [0.5, 1.5, 3.0, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.refresh()
                }
            }
        }
    }

    var desktopRenamerApplicationURL: URL? {
        Self.desktopRenamerBundleIdentifiers
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }

    func openDesktopRenamer() {
        guard let applicationURL = desktopRenamerApplicationURL else { return }
        NSWorkspace.shared.open(applicationURL)

        // DesktopRenamer starts its API listener after launch. Retry the probe
        // while it finishes initializing so the permission page updates without
        // requiring the user to leave and reopen WallPainter.
        for delay in [0.5, 1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }

    func openDesktopRenamerDownloadPage() {
        NSWorkspace.shared.open(Self.desktopRenamerDownloadURL)
    }

    /// Feeds one structured payload through the same validation and revision path
    /// used by distributed-notification events. It is also useful for unit tests.
    func processEventPayloadForTesting(_ payload: String) {
        handleEventPayload(payload)
    }

    /// Handles a correlated response payload for tests and transport diagnostics.
    func processResponsePayloadForTesting(_ payload: String) {
        handleResponsePayload(payload)
    }

    private func installObservers() {
        responseObserver = center.addObserver(
            forName: Self.responseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let payload = notification.userInfo?["payload"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.handleResponsePayload(payload)
            }
        }

        legacyResponseObservers = Self.legacyResponseNotifications.map { name in
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let userInfo = notification.userInfo
                guard let requestID = userInfo?["requestID"] as? String,
                      let succeeded = userInfo?["success"] as? Bool
                else { return }
                let response = LegacySpaceSnapshotResponse(
                    requestID: requestID,
                    succeeded: succeeded,
                    result: userInfo?["result"] as? String
                )
                Task { @MainActor [weak self] in
                    self?.handleLegacySnapshotResponse(response)
                }
            }
        }

        eventObserver = center.addObserver(
            forName: Self.eventNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let payload = notification.userInfo?["payload"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.handleEventPayload(payload)
            }
        }

        apiStateObserver = center.addObserver(
            forName: Self.apiStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let isEnabled = notification.userInfo?["isEnabled"] as? Bool else { return }
            Task { @MainActor [weak self] in
                if isEnabled {
                    self?.requestAPIInfo()
                } else {
                    self?.markUnavailable(as: .disabled)
                }
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let desktopRenamerBundleIdentifiers = Self.desktopRenamerBundleIdentifiers
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            workspaceObservers.append(
                workspaceCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let application = notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication,
                          let bundleIdentifier = application.bundleIdentifier,
                          desktopRenamerBundleIdentifiers.contains(bundleIdentifier)
                    else { return }
                    Task { @MainActor [weak self] in self?.refresh() }
                }
            )
        }
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        )
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        )
        workspaceObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        )
    }

    private func removeObservers() {
        if let responseObserver {
            center.removeObserver(responseObserver)
        }
        for observer in legacyResponseObservers {
            center.removeObserver(observer)
        }
        if let eventObserver {
            center.removeObserver(eventObserver)
        }
        if let apiStateObserver {
            center.removeObserver(apiStateObserver)
        }
        responseObserver = nil
        legacyResponseObservers.removeAll()
        eventObserver = nil
        apiStateObserver = nil

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func requestAPIInfo() {
        guard isRunning, pendingMethods.values.contains("getAPIInfo") == false else { return }
        postRequest(method: "getAPIInfo")
    }

    private func requestSnapshot() {
        guard isRunning, pendingMethods.values.contains("getSpaceSnapshot") == false else { return }
        isWaitingForSnapshot = true
        postRequest(method: "getSpaceSnapshot")
    }

    private var currentDesktopRenamerProcessIdentifier: pid_t? {
        for bundleIdentifier in Self.desktopRenamerBundleIdentifiers {
            if let application = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated }) {
                return application.processIdentifier
            }
        }
        return nil
    }

    /// SpaceAPI revisions are monotonic only within one DesktopRenamer process.
    /// A process change invalidates pending responses from the old revision stream.
    private func synchronizeDesktopRenamerProcess() -> Bool {
        let processIdentifier = currentDesktopRenamerProcessIdentifier
        guard processIdentifier != desktopRenamerProcessIdentifier else { return false }

        desktopRenamerProcessIdentifier = processIdentifier
        beginSnapshotResynchronization()
        cancelPendingRequests()
        return true
    }

    /// API info responses establish a new revision baseline, as required by the
    /// SpaceAPI contract. Ignore events until its full snapshot arrives.
    private func beginSnapshotResynchronization() {
        revisionTracker.reset()
        isWaitingForSnapshot = true
        cancelLegacySnapshotRequest()
    }

    private func cancelPendingRequests() {
        for timeout in pendingTimeouts.values {
            timeout.cancel()
        }
        pendingTimeouts.removeAll()
        pendingMethods.removeAll()
    }

    private func cancelLegacySnapshotRequest() {
        legacySnapshotTimeout?.cancel()
        legacySnapshotTimeout = nil
        legacySnapshotRequestID = nil
        legacySnapshotRevision = nil
        cancelLegacyMappingVerification()
        cancelLegacyMappingRetry()
    }

    private func cancelLegacyMappingVerification() {
        if let requestID = legacyMappingVerificationRequestID {
            pendingMethods.removeValue(forKey: requestID)
            pendingTimeouts.removeValue(forKey: requestID)?.cancel()
        }
        legacyMappingVerificationRequestID = nil
        pendingLegacyMappingValidation = nil
    }

    private func cancelLegacyMappingRetry() {
        legacyMappingRetryWorkItem?.cancel()
        legacyMappingRetryWorkItem = nil
    }

    @discardableResult
    private func postRequest(method: String, params: [String: String]? = nil) -> String? {
        let requestID = UUID().uuidString
        guard let payload = try? SpaceAPICodec.requestPayload(
            id: requestID,
            method: method,
            params: params
        ) else {
            markUnavailable()
            return nil
        }

        pendingMethods[requestID] = method
        let timeout = DispatchWorkItem { [weak self] in
            self?.requestTimedOut(requestID)
        }
        pendingTimeouts[requestID] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)

        center.post(
            name: Self.requestNotification,
            object: nil,
            userInfo: ["payload": payload]
        )
        return requestID
    }

    private func requestTimedOut(_ requestID: String) {
        guard pendingMethods.removeValue(forKey: requestID) != nil else { return }
        pendingTimeouts.removeValue(forKey: requestID)

        if requestID == legacyMappingVerificationRequestID {
            legacyMappingVerificationRequestID = nil
            pendingLegacyMappingValidation = nil
            isWaitingForSnapshot = false
            scheduleLegacyMappingRetry()
            return
        }

        markUnavailable()
    }

    private func handleResponsePayload(_ payload: String) {
        guard let responseID = try? SpaceAPICodec.responseID(from: payload),
              let method = pendingMethods.removeValue(forKey: responseID)
        else { return }

        pendingTimeouts.removeValue(forKey: responseID)?.cancel()
        let mappingValidation = responseID == legacyMappingVerificationRequestID
            ? pendingLegacyMappingValidation
            : nil
        if mappingValidation != nil {
            legacyMappingVerificationRequestID = nil
            pendingLegacyMappingValidation = nil
        }

        if let responseError = try? SpaceAPICodec.responseError(from: payload) {
            let availability: SpaceAPIAvailability = responseError.code == -32001
                ? .disabled
                : .unavailable
            if mappingValidation != nil, availability != .disabled {
                isWaitingForSnapshot = false
                scheduleLegacyMappingRetry()
            } else {
                markUnavailable(as: availability)
                if method == "getSpaceSnapshot" {
                    isWaitingForSnapshot = false
                }
            }
            return
        }

        do {
            if let mappingValidation {
                let freshSnapshot = try SpaceAPICodec.decodeSnapshot(from: payload)
                isWaitingForSnapshot = false

                guard freshSnapshot.revision >= mappingValidation.expectedRevision,
                      revisionTracker.acceptVerifiedSnapshot(revision: freshSnapshot.revision)
                else {
                    scheduleLegacyMappingRetry()
                    return
                }

                guard let mappedSnapshot = freshSnapshot.attachingManagedSpaceIDs(
                    from: mappingValidation.spaces
                ) else {
                    snapshot = freshSnapshot
                    setAvailable(true)
                    postSnapshotDidChange()
                    scheduleLegacyMappingRetry()
                    return
                }

                snapshot = mappedSnapshot
                setAvailable(true)
                legacyMappingRetryCount = 0
                cancelLegacyMappingRetry()
                postSnapshotDidChange()
                return
            }

            switch method {
            case "getAPIInfo":
                let info = try SpaceAPICodec.decodeAPIInfo(from: payload)
                guard info.jsonRPCVersion == "2.0",
                      info.supportedMethods.contains("getSpaceSnapshot")
                else {
                    throw SpaceAPICodecError.unsupportedAPI
                }
                beginSnapshotResynchronization()
                cancelPendingRequests()
                negotiatedAPIInfo = info
                setAvailable(true)
                requestSnapshot()

            case "getSpaceSnapshot":
                let newSnapshot = try SpaceAPICodec.decodeSnapshot(from: payload)
                isWaitingForSnapshot = false
                applySnapshot(newSnapshot, isEvent: false)

            default:
                break
            }
        } catch {
            if mappingValidation != nil {
                isWaitingForSnapshot = false
                scheduleLegacyMappingRetry()
                return
            }
            if method == "getSpaceSnapshot" {
                isWaitingForSnapshot = false
            }
            markUnavailable()
        }
    }

    private func handleEventPayload(_ payload: String) {
        guard isRunning,
              !isWaitingForSnapshot,
              let eventSnapshot = try? SpaceAPICodec.decodeStateChangedEvent(from: payload)
        else { return }

        switch revisionTracker.evaluateEvent(revision: eventSnapshot.revision) {
        case .apply:
            applySnapshot(eventSnapshot, isEvent: true)
        case .stale:
            return
        case .gap:
            isWaitingForSnapshot = true
            requestSnapshot()
        }
    }

    private func applySnapshot(_ newSnapshot: SpaceSnapshot, isEvent: Bool) {
        if !isEvent {
            guard revisionTracker.acceptSnapshot(revision: newSnapshot.revision) else { return }
            isWaitingForSnapshot = false
        }
        cancelLegacySnapshotRequest()
        cancelLegacyMappingRetry()
        snapshot = newSnapshot
        setAvailable(true)
        postSnapshotDidChange()
        requestLegacySnapshot(for: newSnapshot)
    }

    private func requestLegacySnapshot(for structuredSnapshot: SpaceSnapshot) {
        legacySnapshotTimeout?.cancel()

        let requestID = UUID().uuidString
        legacySnapshotRequestID = requestID
        legacySnapshotRevision = structuredSnapshot.revision

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.legacySnapshotRequestID == requestID else { return }
            self.legacySnapshotRequestID = nil
            self.legacySnapshotRevision = nil
            self.legacySnapshotTimeout = nil
            self.scheduleLegacyMappingRetry()
        }
        legacySnapshotTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)

        center.post(
            name: Self.legacyRequestNotification,
            object: nil,
            userInfo: ["requestID": requestID, "command": "getSpaceSnapshot"]
        )
    }

    private func handleLegacySnapshotResponse(_ response: LegacySpaceSnapshotResponse) {
        guard response.requestID == legacySnapshotRequestID,
              let revision = legacySnapshotRevision,
              snapshot?.revision == revision,
              response.succeeded,
              let result = response.result,
              let legacySpaces = try? SpaceAPICodec.decodeLegacySpaceSnapshot(from: result)
        else { return }

        legacySnapshotTimeout?.cancel()
        legacySnapshotTimeout = nil
        legacySnapshotRequestID = nil
        legacySnapshotRevision = nil

        pendingLegacyMappingValidation = LegacySpaceMappingValidation(
            expectedRevision: revision,
            spaces: legacySpaces
        )
        isWaitingForSnapshot = true
        guard let requestID = postRequest(method: "getSpaceSnapshot") else {
            pendingLegacyMappingValidation = nil
            isWaitingForSnapshot = false
            scheduleLegacyMappingRetry()
            return
        }
        legacyMappingVerificationRequestID = requestID
    }

    private func scheduleLegacyMappingRetry() {
        guard isRunning else { return }
        cancelLegacyMappingRetry()
        legacyMappingRetryCount += 1
        let delay = min(pow(2, Double(legacyMappingRetryCount - 1)), 16)
        let retry = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.legacyMappingRetryWorkItem = nil
            self.refresh()
        }
        legacyMappingRetryWorkItem = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: retry)
    }

    private func postSnapshotDidChange() {
        NotificationCenter.default.post(
            name: .wallPainterSpaceSnapshotDidChange,
            object: self
        )
    }

    private func markUnavailable(
        as availability: SpaceAPIAvailability = .unavailable
    ) {
        cancelLegacySnapshotRequest()
        snapshot = nil
        negotiatedAPIInfo = nil
        revisionTracker.reset()
        isWaitingForSnapshot = false
        apiAvailability = availability
        setAvailable(false)
    }

    private func setAvailable(_ value: Bool) {
        if value {
            apiAvailability = .available
        }
        guard isAvailable != value else { return }
        let wasAvailable = isAvailable
        isAvailable = value
        disconnectNotifications.availabilityDidChange(
            from: wasAvailable,
            to: value
        )
        NotificationCenter.default.post(
            name: .wallPainterSpaceAvailabilityDidChange,
            object: self
        )
    }
}
