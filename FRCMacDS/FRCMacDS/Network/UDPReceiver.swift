import Foundation
import Darwin

/// Listens on UDP port 1150 for Robot → DS status packets.
/// Uses a GCD read source on a POSIX socket for reliable packet receipt.
final class UDPReceiver {
    private var sockfd:     Int32 = -1
    private var readSource: DispatchSourceRead?

    var onReceive: ((Data) -> Void)?
    var onLog: ((String) -> Void)?

    private func log(_ text: String) {
        onLog?(text)
    }

    func start() {
        stop()

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            log("UDPReceiver: socket() failed: \(String(cString: strerror(errno)))")
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr         = sockaddr_in()
        addr.sin_family  = sa_family_t(AF_INET)
        addr.sin_port    = UInt16(1150).bigEndian
        addr.sin_addr    = in_addr(s_addr: INADDR_ANY)

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            log("UDPReceiver: bind() failed: \(String(cString: strerror(errno)))")
            close(fd)
            return
        }

        sockfd = fd
        log("UDPReceiver: bound to port 1150")

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.readPacket() }
        source.resume()
        readSource = source
    }

    private func readPacket() {
        var buf = [UInt8](repeating: 0, count: 1500)
        let n = recv(sockfd, &buf, buf.count, 0)
        guard n > 0 else { return }
        let data = Data(buf.prefix(n))
        onReceive?(data)
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        if sockfd >= 0 { close(sockfd); sockfd = -1 }
    }
}
