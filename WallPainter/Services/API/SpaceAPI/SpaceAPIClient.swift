import AppKit
import Darwin
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
    /// Current-session macOS ID for system calls; persist the stable `id` instead.
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
    var hasCompleteManagedSpaceIDs: Bool {
        spaces.allSatisfy { $0.managedSpaceID != nil }
    }

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
                managedSpaceID: space.managedSpaceID ?? managedIDsByPosition[SpacePositionKey(space)]
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
    let legacyNotifications: Bool?
    let legacyCompatibility: String?
    let transports: [String]?
    let socketEndpoint: String?
    let accessRestricted: Bool?
}

enum SpaceAPIAvailability: Equatable, Sendable {
    case available
    case connecting
    case disabled
    case accessDenied
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
        "dev.mqiu.DesktopRenamer.RPCRequest"
    )
    static let responseNotification = Notification.Name(
        "dev.mqiu.DesktopRenamer.RPCResponse"
    )
    static let eventNotification = Notification.Name(
        "dev.mqiu.DesktopRenamer.RPCEvent"
    )
    static let apiStateNotification = Notification.Name(
        "dev.mqiu.DesktopRenamer.ReturnAPIState"
    )
    private static let compatibilityRequestNotification = Notification.Name(
        "com.michaelqiu.DesktopRenamer.RPCRequest"
    )
    private static let responseNotifications = [
        responseNotification,
        Notification.Name("com.michaelqiu.DesktopRenamer.RPCResponse")
    ]
    private static let eventNotifications = [
        eventNotification,
        Notification.Name("com.michaelqiu.DesktopRenamer.RPCEvent")
    ]
    private static let apiStateNotifications = [
        apiStateNotification,
        Notification.Name("com.michaelqiu.DesktopRenamer.ReturnAPIState")
    ]
    static let legacyRequestNotification = Notification.Name(
        "dev.mqiu.DesktopRenamer.PerformCommand"
    )
    private static let compatibilityLegacyRequestNotification = Notification.Name(
        "com.michaelqiu.DesktopRenamer.PerformCommand"
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
    @ObservationIgnored private let socketTransport = SpaceAPISocketTransport()
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var usesCompatibilityNotificationNamespace = false
    @ObservationIgnored private var responseObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var legacyResponseObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var eventObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var apiStateObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingMethods: [String: String] = [:]
    @ObservationIgnored private var pendingTimeouts: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private var revisionTracker = SpaceAPIRevisionTracker()
    @ObservationIgnored private var isWaitingForSnapshot = false
    @ObservationIgnored private var desktopRenamerProcessIdentifier: pid_t?
    @ObservationIgnored private var usesSocketTransport = false
    @ObservationIgnored private var socketTransportSupported = false
    @ObservationIgnored private var socketEndpointPath: String?
    @ObservationIgnored private var socketProbeWorkItems: [DispatchWorkItem] = []
    @ObservationIgnored private var legacySnapshotRequestID: String?
    @ObservationIgnored private var legacySnapshotRevision: UInt64?
    @ObservationIgnored private var legacySnapshotTimeout: DispatchWorkItem?
    @ObservationIgnored private var legacyMappingVerificationRequestID: String?
    @ObservationIgnored private var pendingLegacyMappingValidation: LegacySpaceMappingValidation?
    @ObservationIgnored private var legacyMappingRetryWorkItem: DispatchWorkItem?
    @ObservationIgnored private var legacyMappingRetryCount = 0

    init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    func start() {
        stop()
        isRunning = true
        usesCompatibilityNotificationNamespace = false
        desktopRenamerProcessIdentifier = currentDesktopRenamerProcessIdentifier
        isWaitingForSnapshot = true
        socketTransport.onReady = { [weak self] in
            guard let self, self.isRunning else { return }
            self.usesSocketTransport = true
            self.apiAvailability = .connecting
            self.beginSnapshotResynchronization()
            self.cancelPendingRequests()
            self.requestAPIInfo()
        }
        socketTransport.onPayload = { [weak self] payload in
            self?.handleSocketPayload(payload)
        }
        socketTransport.onFailure = { [weak self] in
            guard let self, self.isRunning, self.usesSocketTransport else { return }
            self.cancelPendingRequests()
            self.markUnavailable()
        }
        installObservers()
        connectPreferredTransport()
    }

    func stop() {
        isRunning = false
        usesCompatibilityNotificationNamespace = false
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
        cancelSocketProbes()
        socketTransport.cancel()
        usesSocketTransport = false
        socketTransportSupported = false
        socketEndpointPath = nil
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

        if processChanged {
            socketTransport.cancel()
            usesSocketTransport = false
            socketTransportSupported = false
            socketEndpointPath = nil
            usesCompatibilityNotificationNamespace = false
            negotiatedAPIInfo = nil
        }
        connectPreferredTransport()

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
        responseObservers = Self.responseNotifications.map { name in
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let payload = notification.userInfo?["payload"] as? String else { return }
                Task { @MainActor [weak self] in
                    self?.handleResponsePayload(payload)
                }
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

        eventObservers = Self.eventNotifications.map { name in
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let payload = notification.userInfo?["payload"] as? String else { return }
                Task { @MainActor [weak self] in
                    self?.handleEventPayload(payload)
                }
            }
        }

        apiStateObservers = Self.apiStateNotifications.map { name in
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let isEnabled = notification.userInfo?["isEnabled"] as? Bool else { return }
                Task { @MainActor [weak self] in
                    if isEnabled {
                        self?.refresh()
                    } else {
                        self?.markUnavailable(as: .disabled)
                    }
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
        for observer in responseObservers {
            center.removeObserver(observer)
        }
        for observer in legacyResponseObservers {
            center.removeObserver(observer)
        }
        for observer in eventObservers {
            center.removeObserver(observer)
        }
        for observer in apiStateObservers {
            center.removeObserver(observer)
        }
        responseObservers.removeAll()
        legacyResponseObservers.removeAll()
        eventObservers.removeAll()
        apiStateObservers.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func requestAPIInfo() {
        guard isRunning, pendingMethods.values.contains("getAPIInfo") == false else { return }
        guard !usesSocketTransport || socketTransport.isReady else { return }
        postRequest(method: "getAPIInfo")
    }

    private func requestSnapshot() {
        guard isRunning, pendingMethods.values.contains("getSpaceSnapshot") == false else { return }
        guard !usesSocketTransport || socketTransport.isReady else { return }
        isWaitingForSnapshot = true
        postRequest(method: "getSpaceSnapshot")
    }

    private var defaultSocketEndpointPath: String {
        "/tmp/dev.mqiu.DesktopRenamer-\(getuid()).sock"
    }

    private var preferredSocketEndpointPath: String {
        negotiatedAPIInfo?.socketEndpoint
            ?? socketEndpointPath
            ?? defaultSocketEndpointPath
    }

    private func connectPreferredTransport() {
        guard isRunning else { return }

        if let negotiatedAPIInfo {
            guard negotiatedAPIInfo.transports?.contains("unixDomainSocket") == true else {
                socketTransportSupported = false
                usesSocketTransport = false
                cancelSocketProbes()
                requestAPIInfo()
                return
            }

            socketTransportSupported = true
            connectToSocket(at: preferredSocketEndpointPath)
            return
        }

        if socketTransportSupported
            || FileManager.default.fileExists(atPath: defaultSocketEndpointPath) {
            socketTransportSupported = true
            connectToSocket(at: preferredSocketEndpointPath)
            return
        }

        usesSocketTransport = false
        apiAvailability = .connecting
        requestAPIInfo()
        scheduleSocketProbes()
    }

    private func connectToSocket(at path: String) {
        guard isRunning else { return }
        if socketTransport.endpointPath == path, socketTransport.isConnectingOrReady {
            if socketTransport.isReady {
                requestAPIInfo()
            }
            return
        }

        usesSocketTransport = true
        socketTransportSupported = true
        socketEndpointPath = path
        apiAvailability = .connecting
        cancelSocketProbes()
        cancelPendingRequests()
        beginSnapshotResynchronization()
        socketTransport.connect(path: path)
    }

    private func scheduleSocketProbes() {
        guard isRunning, !socketTransportSupported else { return }
        cancelSocketProbes()

        for delay in [0.5, 1.5, 3.0, 5.0] {
            let probe = DispatchWorkItem { [weak self] in
                guard let self, self.isRunning,
                      !self.socketTransportSupported,
                      self.negotiatedAPIInfo?.transports?.contains("unixDomainSocket") != false
                else { return }
                if FileManager.default.fileExists(atPath: self.defaultSocketEndpointPath) {
                    self.connectToSocket(at: self.defaultSocketEndpointPath)
                }
            }
            socketProbeWorkItems.append(probe)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: probe)
        }
    }

    private func cancelSocketProbes() {
        for probe in socketProbeWorkItems {
            probe.cancel()
        }
        socketProbeWorkItems.removeAll()
    }

    private func handleSocketPayload(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if object.keys.contains("id") {
            handleResponsePayload(payload)
        } else {
            handleEventPayload(payload)
        }
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
        let timeoutInterval: TimeInterval = method == "getAPIInfo" && usesSocketTransport
            ? 120
            : 3
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)

        if usesSocketTransport {
            do {
                try socketTransport.send(payload)
            } catch {
                pendingTimeouts.removeValue(forKey: requestID)?.cancel()
                pendingMethods.removeValue(forKey: requestID)
                markUnavailable()
                return nil
            }
        } else {
            let name = usesCompatibilityNotificationNamespace
                ? Self.compatibilityRequestNotification
                : Self.requestNotification
            center.post(name: name, object: nil, userInfo: ["payload": payload])
        }
        return requestID
    }

    private func requestTimedOut(_ requestID: String) {
        guard let pendingMethod = pendingMethods.removeValue(forKey: requestID) else { return }
        pendingTimeouts.removeValue(forKey: requestID)

        if requestID == legacyMappingVerificationRequestID {
            legacyMappingVerificationRequestID = nil
            pendingLegacyMappingValidation = nil
            isWaitingForSnapshot = false
            scheduleLegacyMappingRetry()
            return
        }

        if pendingMethod == "getAPIInfo",
           !usesSocketTransport,
           !usesCompatibilityNotificationNamespace {
            usesCompatibilityNotificationNamespace = true
            requestAPIInfo()
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
            let availability: SpaceAPIAvailability
            switch responseError.code {
            case -32001:
                availability = .disabled
            case -32003:
                availability = .accessDenied
            default:
                availability = .unavailable
            }
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

                let verifiedSnapshot = freshSnapshot.hasCompleteManagedSpaceIDs
                    ? freshSnapshot
                    : freshSnapshot.attachingManagedSpaceIDs(from: mappingValidation.spaces)
                guard let verifiedSnapshot else {
                    snapshot = freshSnapshot
                    setAvailable(true)
                    postSnapshotDidChange()
                    scheduleLegacyMappingRetry()
                    return
                }

                snapshot = verifiedSnapshot
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
                      supportsContractVersion(info.contractVersion),
                      info.supportedMethods.contains("getSpaceSnapshot")
                else {
                    throw SpaceAPICodecError.unsupportedAPI
                }

                if info.transports?.contains("unixDomainSocket") == true {
                    socketTransportSupported = true
                    let endpointPath = info.socketEndpoint ?? defaultSocketEndpointPath
                    socketEndpointPath = endpointPath
                    if !usesSocketTransport || socketTransport.endpointPath != endpointPath {
                        connectToSocket(at: endpointPath)
                        return
                    }
                } else if !usesSocketTransport {
                    socketTransportSupported = false
                    cancelSocketProbes()
                    guard info.transports?.contains("distributedNotificationCenter") != false else {
                        throw SpaceAPICodecError.unsupportedAPI
                    }
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

    private func supportsContractVersion(_ version: String) -> Bool {
        let components = version.split(separator: ".")
        guard components.count == 3,
              let major = Int(components[0]),
              Int(components[1]) != nil,
              Int(components[2]) != nil
        else { return false }
        return major == 1
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
        guard !newSnapshot.hasCompleteManagedSpaceIDs,
              negotiatedAPIInfo?.legacyNotifications != false,
              negotiatedAPIInfo?.legacyCompatibility != "disabledByAccessPolicy"
        else {
            legacyMappingRetryCount = 0
            return
        }
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

        let name = usesCompatibilityNotificationNamespace
            ? Self.compatibilityLegacyRequestNotification
            : Self.legacyRequestNotification
        center.post(
            name: name,
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
        isAvailable = value
        NotificationCenter.default.post(
            name: .wallPainterSpaceAvailabilityDidChange,
            object: self
        )
    }
}
