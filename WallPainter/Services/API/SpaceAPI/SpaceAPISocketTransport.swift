import Foundation
import Network

enum SpaceAPISocketFrameError: Error {
    case payloadTooLarge
    case invalidFrameLength
    case invalidUTF8
    case notConnected
}

enum SpaceAPISocketFrameCodec {
    static let maximumPayloadLength = 1_048_576

    static func encode(_ payload: String) throws -> Data {
        let payloadData = Data(payload.utf8)
        guard !payloadData.isEmpty,
              payloadData.count <= maximumPayloadLength,
              let length = UInt32(exactly: payloadData.count)
        else {
            throw SpaceAPISocketFrameError.payloadTooLarge
        }

        var frame = Data([
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff)
        ])
        frame.append(payloadData)
        return frame
    }

    static func extractMessages(from buffer: inout Data) throws -> [String] {
        var messages: [String] = []

        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = (UInt32(buffer[start]) << 24)
                | (UInt32(buffer[start + 1]) << 16)
                | (UInt32(buffer[start + 2]) << 8)
                | UInt32(buffer[start + 3])

            guard length > 0, length <= maximumPayloadLength else {
                throw SpaceAPISocketFrameError.invalidFrameLength
            }

            let frameLength = 4 + Int(length)
            guard buffer.count >= frameLength else { break }

            let payloadStart = start + 4
            let payloadEnd = payloadStart + Int(length)
            let payloadData = buffer.subdata(in: payloadStart..<payloadEnd)
            guard let message = String(data: payloadData, encoding: .utf8) else {
                throw SpaceAPISocketFrameError.invalidUTF8
            }

            messages.append(message)
            buffer.removeSubrange(start..<payloadEnd)
        }

        return messages
    }
}

@MainActor
final class SpaceAPISocketTransport {
    private let queue = DispatchQueue(label: "dev.mqiu.WallPainter.spaceapi.socket")
    private var connection: NWConnection?
    private var connectionGeneration = 0
    private var receiveBuffer = Data()

    private(set) var endpointPath: String?
    private(set) var isConnectingOrReady = false
    private(set) var isReady = false

    var onReady: (() -> Void)?
    var onPayload: ((String) -> Void)?
    var onFailure: (() -> Void)?

    func connect(path: String) {
        guard !path.isEmpty else {
            onFailure?()
            return
        }
        guard endpointPath != path || !isConnectingOrReady else { return }

        cancel()
        connectionGeneration += 1
        let generation = connectionGeneration
        endpointPath = path
        isConnectingOrReady = true
        receiveBuffer.removeAll(keepingCapacity: true)

        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor [weak self] in
                    self?.handleReady(generation: generation)
                }
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    self?.handleFailure(generation: generation)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connectionGeneration += 1
        let connection = self.connection
        self.connection = nil
        endpointPath = nil
        isConnectingOrReady = false
        isReady = false
        receiveBuffer.removeAll(keepingCapacity: false)
        connection?.stateUpdateHandler = nil
        connection?.cancel()
    }

    func send(_ payload: String) throws {
        guard isReady, let connection else {
            throw SpaceAPISocketFrameError.notConnected
        }
        let frame = try SpaceAPISocketFrameCodec.encode(payload)
        let generation = connectionGeneration
        connection.send(
            content: frame,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                guard error != nil else { return }
                Task { @MainActor [weak self] in
                    self?.handleFailure(generation: generation)
                }
            }
        )
    }

    private func handleReady(generation: Int) {
        guard connectionGeneration == generation,
              connection != nil,
              isConnectingOrReady
        else { return }

        isReady = true
        onReady?()
        receiveNext(generation: generation)
    }

    private func receiveNext(generation: Int) {
        guard connectionGeneration == generation,
              isReady,
              let connection
        else { return }

        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: SpaceAPISocketFrameCodec.maximumPayloadLength + 4
        ) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self, self.connectionGeneration == generation else { return }

                if let data {
                    self.receiveBuffer.append(data)
                    do {
                        for message in try SpaceAPISocketFrameCodec.extractMessages(
                            from: &self.receiveBuffer
                        ) {
                            self.onPayload?(message)
                        }
                    } catch {
                        self.handleFailure(generation: generation)
                        return
                    }
                }

                guard error == nil, !isComplete else {
                    self.handleFailure(generation: generation)
                    return
                }

                self.receiveNext(generation: generation)
            }
        }
    }

    private func handleFailure(generation: Int) {
        guard connectionGeneration == generation else { return }

        connectionGeneration += 1
        let connection = self.connection
        self.connection = nil
        endpointPath = nil
        isConnectingOrReady = false
        isReady = false
        receiveBuffer.removeAll(keepingCapacity: false)
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        onFailure?()
    }
}
