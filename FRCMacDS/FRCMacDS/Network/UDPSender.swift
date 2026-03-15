import Foundation
import Network

/// Sends DS → Robot UDP control packets at 50 Hz on port 1110.
final class UDPSender {
    private var connection: NWConnection?
    private var sendTask:   Task<Void, Never>?

    var onSendPacket: (() -> Data)?
    private(set) var isRunning = false

    func start(host: String) {
        stop()
        let params = NWParameters.udp
        connection = NWConnection(host: NWEndpoint.Host(host), port: 1110, using: params)
        connection?.start(queue: .main)
        isRunning = true

        sendTask = Task { [weak self] in
            let clock    = ContinuousClock()
            let interval = Duration.milliseconds(20)
            var next     = clock.now

            while !Task.isCancelled {
                if let data = self?.onSendPacket?() {
                    self?.connection?.send(content: data, completion: .idempotent)
                }
                next += interval
                try? await clock.sleep(until: next, tolerance: .milliseconds(2))
            }
        }
    }

    func stop() {
        sendTask?.cancel()
        sendTask = nil
        connection?.cancel()
        connection = nil
        isRunning  = false
    }
}
