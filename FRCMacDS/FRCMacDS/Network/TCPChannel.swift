import Foundation
import Network

/// Bidirectional TCP connection to the robot on port 1740.
/// Messages are framed: [size_hi][size_lo][tagID][payload...]
/// where size = 1 + len(payload).
final class TCPChannel {
    private var connection:    NWConnection?
    private var receiveBuffer: Data = Data()

    var onMessage:      ((UInt8, Data) -> Void)?
    var onConnected:    (() -> Void)?
    var onDisconnected: (() -> Void)?

    func connect(to host: String) {
        disconnect()
        connection = NWConnection(host: NWEndpoint.Host(host), port: 1740, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onConnected?()
                self?.receiveLoop()
            case .failed, .cancelled:
                self?.connection = nil
                self?.onDisconnected?()
            default: break
            }
        }
        connection?.start(queue: .main)
    }

    // MARK: - Sending

    func send(tagID: UInt8, payload: Data = Data()) {
        var msg  = Data()
        let size = UInt16(1 + payload.count)
        msg.append(UInt8(size >> 8))
        msg.append(UInt8(size & 0xFF))
        msg.append(tagID)
        msg.append(payload)
        connection?.send(content: msg, completion: .idempotent)
    }

    // MARK: - Receiving

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                self?.processReceived(data)
            }
            if !isComplete && error == nil {
                self?.receiveLoop()
            }
        }
    }

    private func processReceived(_ data: Data) {
        receiveBuffer.append(data)
        while receiveBuffer.count >= 3 {
            let msgSize   = Int(receiveBuffer[0]) << 8 | Int(receiveBuffer[1])
            let totalSize = msgSize + 2
            guard receiveBuffer.count >= totalSize, msgSize >= 1 else { break }
            let tagID   = receiveBuffer[2]
            let payload = receiveBuffer.subdata(in: 3..<totalSize)
            onMessage?(tagID, payload)
            receiveBuffer.removeFirst(totalSize)
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
    }
}
