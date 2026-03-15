import Foundation
import Network

/// Listens on UDP port 1150 for Robot → DS status packets.
final class UDPReceiver {
    private var listener: NWListener?

    var onReceive: ((Data) -> Void)?

    func start() {
        stop()
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: 1150)
            listener?.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                self?.receiveLoop(conn)
            }
            listener?.start(queue: .main)
        } catch {
            print("UDPReceiver start error: \(error)")
        }
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data { self?.onReceive?(data) }
            if error == nil { self?.receiveLoop(connection) }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
