import Foundation

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
