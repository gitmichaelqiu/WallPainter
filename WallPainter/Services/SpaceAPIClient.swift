import AppKit
import Foundation
import Observation

struct SpaceDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let displayID: String
    let displayName: String
    let number: Int
    let isFullscreen: Bool
}

struct SpaceSnapshot: Codable, Equatable, Sendable {
    let revision: UInt64
    let currentSpaceIDs: [String]
    let spaces: [SpaceDescriptor]
}

struct SpaceAPIInfo: Codable, Equatable, Sendable {
    let contractVersion: String
    let jsonRPCVersion: String
    let supportedMethods: [String]
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

enum SpaceAPICodec {
    private static let jsonRPCVersion = "2.0"

    static func requestPayload(
        id: String,
        method: String,
        params: [String: String]? = nil
    ) throws -> String {
        guard !id.isEmpty, !method.isEmpty else {
            throw SpaceAPICodecError.invalidResponse
        }

        var request: [String: Any] = [
            "jsonrpc": jsonRPCVersion,
            "id": id,
            "method": method
        ]
        if let params {
            request["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        guard let payload = String(data: data, encoding: .utf8) else {
            throw SpaceAPICodecError.invalidPayload
        }
        return payload
    }

    static func responseID(from payload: String) throws -> String? {
        let object = try object(from: payload)
        guard object["jsonrpc"] as? String == jsonRPCVersion else {
            throw SpaceAPICodecError.invalidResponse
        }
        guard object.keys.contains("id") else {
            throw SpaceAPICodecError.invalidResponse
        }
        return object["id"] as? String
    }

    static func responseError(from payload: String) throws -> SpaceAPIError? {
        let object = try object(from: payload)
        guard let error = object["error"] as? [String: Any] else { return nil }
        guard let code = (error["code"] as? NSNumber)?.intValue,
              let message = error["message"] as? String
        else {
            throw SpaceAPICodecError.invalidResponse
        }
        return SpaceAPIError(code: code, message: message)
    }

    static func decodeAPIInfo(from payload: String) throws -> SpaceAPIInfo {
        let object = try object(from: payload)
        let result = try resultObject(from: object)
        guard let contractVersion = result["contractVersion"] as? String,
              let jsonRPCVersion = result["jsonRPCVersion"] as? String,
              let supportedMethods = result["supportedMethods"] as? [String]
        else {
            throw SpaceAPICodecError.invalidResponse
        }

        return SpaceAPIInfo(
            contractVersion: contractVersion,
            jsonRPCVersion: jsonRPCVersion,
            supportedMethods: supportedMethods
        )
    }

    static func decodeSnapshot(from payload: String) throws -> SpaceSnapshot {
        let object = try object(from: payload)
        return try decodeSnapshotObject(resultObject(from: object))
    }

    static func decodeStateChangedEvent(from payload: String) throws -> SpaceSnapshot? {
        let object = try object(from: payload)
        guard object["jsonrpc"] as? String == jsonRPCVersion,
              object["method"] as? String == "stateChanged",
              let params = object["params"] as? [String: Any]
        else {
            throw SpaceAPICodecError.invalidResponse
        }

        guard let snapshot = params["snapshot"] as? [String: Any] else {
            return nil
        }
        return try decodeSnapshotObject(snapshot)
    }

    private static func object(from payload: String) throws -> [String: Any] {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            throw SpaceAPICodecError.invalidPayload
        }
        return dictionary
    }

    private static func resultObject(from object: [String: Any]) throws -> [String: Any] {
        guard object["jsonrpc"] as? String == jsonRPCVersion,
              let result = object["result"] as? [String: Any]
        else {
            throw SpaceAPICodecError.invalidResponse
        }
        return result
    }

    private static func decodeSnapshotObject(_ object: [String: Any]) throws -> SpaceSnapshot {
        guard let revision = (object["revision"] as? NSNumber)?.uint64Value,
              let currentSpaceIDs = object["currentSpaceIDs"] as? [String],
              let spaces = object["spaces"] as? [[String: Any]]
        else {
            throw SpaceAPICodecError.invalidResponse
        }

        let descriptors = try spaces.map { space -> SpaceDescriptor in
            guard let id = space["id"] as? String,
                  let name = space["name"] as? String,
                  let displayID = space["displayID"] as? String,
                  let displayName = space["displayName"] as? String,
                  let number = (space["number"] as? NSNumber)?.intValue,
                  let isFullscreen = (space["isFullscreen"] as? NSNumber)?.boolValue
            else {
                throw SpaceAPICodecError.invalidResponse
            }

            return SpaceDescriptor(
                id: id,
                name: name,
                displayID: displayID,
                displayName: displayName,
                number: number,
                isFullscreen: isFullscreen
            )
        }

        return SpaceSnapshot(
            revision: revision,
            currentSpaceIDs: currentSpaceIDs,
            spaces: descriptors
        )
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

    private(set) var snapshot: SpaceSnapshot?
    private(set) var isAvailable = false
    private(set) var negotiatedAPIInfo: SpaceAPIInfo?

    @ObservationIgnored private let center: DistributedNotificationCenter
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var responseObserver: NSObjectProtocol?
    @ObservationIgnored private var eventObserver: NSObjectProtocol?
    @ObservationIgnored private var apiStateObserver: NSObjectProtocol?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingMethods: [String: String] = [:]
    @ObservationIgnored private var pendingTimeouts: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private var revisionTracker = SpaceAPIRevisionTracker()
    @ObservationIgnored private var isWaitingForSnapshot = false

    init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    func start() {
        stop()
        isRunning = true
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
        revisionTracker.reset()
        isWaitingForSnapshot = false
        negotiatedAPIInfo = nil
        snapshot = nil
        setAvailable(false)
    }

    func refresh() {
        guard isRunning else { return }
        requestAPIInfo()
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
                    self?.markUnavailable()
                }
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
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
        if let eventObserver {
            center.removeObserver(eventObserver)
        }
        if let apiStateObserver {
            center.removeObserver(apiStateObserver)
        }
        responseObserver = nil
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

    private func postRequest(method: String, params: [String: String]? = nil) {
        let requestID = UUID().uuidString
        guard let payload = try? SpaceAPICodec.requestPayload(
            id: requestID,
            method: method,
            params: params
        ) else {
            markUnavailable()
            return
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
    }

    private func requestTimedOut(_ requestID: String) {
        guard pendingMethods.removeValue(forKey: requestID) != nil else { return }
        pendingTimeouts.removeValue(forKey: requestID)
        markUnavailable()
    }

    private func handleResponsePayload(_ payload: String) {
        guard let responseID = try? SpaceAPICodec.responseID(from: payload),
              let method = pendingMethods.removeValue(forKey: responseID)
        else { return }

        pendingTimeouts.removeValue(forKey: responseID)?.cancel()

        if (try? SpaceAPICodec.responseError(from: payload)) != nil {
            markUnavailable()
            if method == "getSpaceSnapshot" {
                isWaitingForSnapshot = false
            }
            return
        }

        do {
            switch method {
            case "getAPIInfo":
                let info = try SpaceAPICodec.decodeAPIInfo(from: payload)
                guard info.jsonRPCVersion == "2.0",
                      info.supportedMethods.contains("getSpaceSnapshot")
                else {
                    throw SpaceAPICodecError.unsupportedAPI
                }
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
            if method == "getSpaceSnapshot" {
                isWaitingForSnapshot = false
            }
            markUnavailable()
        }
    }

    private func handleEventPayload(_ payload: String) {
        guard isRunning,
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
        snapshot = newSnapshot
        setAvailable(true)
        NotificationCenter.default.post(
            name: .wallPainterSpaceSnapshotDidChange,
            object: self
        )
    }

    private func markUnavailable() {
        snapshot = nil
        negotiatedAPIInfo = nil
        revisionTracker.reset()
        isWaitingForSnapshot = false
        setAvailable(false)
    }

    private func setAvailable(_ value: Bool) {
        guard isAvailable != value else { return }
        isAvailable = value
        NotificationCenter.default.post(
            name: .wallPainterSpaceAvailabilityDidChange,
            object: self
        )
    }
}
