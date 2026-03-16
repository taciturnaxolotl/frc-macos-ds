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
    private(set) var isRunning = false

    func start(host: String) {
        stop()

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            print("[UDPSender] socket() failed: \(String(cString: strerror(errno)))")
            return
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to local port 1110 — robot expects source port 1110
        var local        = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port   = UInt16(1110).bigEndian
        local.sin_addr   = in_addr(s_addr: INADDR_ANY)
        withUnsafePointer(to: &local) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                let r = bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                if r != 0 { print("[UDPSender] bind: \(String(cString: strerror(errno)))") }
            }
        }

        sockfd = fd

        var addr         = sockaddr_in()
        addr.sin_family  = sa_family_t(AF_INET)
        addr.sin_port    = UInt16(1110).bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        destAddr = addr

        isRunning = true
        print("[UDPSender] socket \(fd), bound :1110 → \(host):1110")

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
                            print("[UDPSender] sendto: \(String(cString: strerror(e)))")
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
