import Foundation
import Darwin

/// Sends DS → Robot UDP control packets at 50 Hz on port 1110.
/// Uses POSIX sendto() directly — no connection state machine, sends immediately.
final class UDPSender {
    private var sockfd:        Int32 = -1
    private var sendTask:      Task<Void, Never>?
    private var destAddr:      sockaddr_in?
    private var lastErrErrno:  Int32 = 0
    private var lastErrPrinted = ContinuousClock.now

    var onSendPacket: (() -> Data)?
    var onLog: ((String) -> Void)?
    private(set) var isRunning = false

    private func log(_ text: String) {
        onLog?(text)
    }

    func start(host: String) {
        stop()

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            log("UDPSender: socket() failed: \(String(cString: strerror(errno)))")
            return
        }
        sockfd = fd

        var addr         = sockaddr_in()
        addr.sin_family  = sa_family_t(AF_INET)
        addr.sin_port    = UInt16(1110).bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        destAddr = addr

        isRunning = true
        log("UDPSender: socket \(fd), sending to \(host):1110")

        sendTask = Task { @MainActor [weak self] in
            let clock    = ContinuousClock()
            let interval = Duration.milliseconds(20)
            var next     = clock.now

            while !Task.isCancelled {
                if let self, let data = self.onSendPacket?() {
                    self.send(data)
                }
                next += interval
                try? await clock.sleep(until: next, tolerance: .milliseconds(2))
            }
        }
    }

    private func send(_ data: Data) {
        guard sockfd >= 0, var addr = destAddr else { return }
        data.withUnsafeBytes { buf in
            withUnsafeMutablePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    let n = sendto(sockfd, buf.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    if n < 0 {
                        let e = errno
                        let now = ContinuousClock.now
                        if e != self.lastErrErrno || now - self.lastErrPrinted > .seconds(5) {
                            self.log("UDPSender: sendto failed: \(String(cString: strerror(e)))")
                            self.lastErrErrno  = e
                            self.lastErrPrinted = now
                        }
                    } else {
                        self.lastErrErrno = 0
                    }
                }
            }
        }
    }

    func stop() {
        sendTask?.cancel()
        sendTask = nil
        if sockfd >= 0 { close(sockfd); sockfd = -1 }
        destAddr  = nil
        isRunning = false
    }
}
