import Foundation

// Robot → DS UDP packet (sent from RoboRIO to DS on port 1150)
struct RobotStatus {
    struct StatusFlags: OptionSet {
        var rawValue: UInt8
        static let estop    = StatusFlags(rawValue: 1 << 7)
        static let brownout = StatusFlags(rawValue: 1 << 4)
        static let codeInit = StatusFlags(rawValue: 1 << 3)
        static let enabled  = StatusFlags(rawValue: 1 << 2)
    }

    struct TraceFlags: OptionSet {
        var rawValue: UInt8
        static let robotCode = TraceFlags(rawValue: 1 << 5)  // code actively running
        static let isRoboRIO = TraceFlags(rawValue: 1 << 4)
    }

    let sequenceNumber: UInt16
    let status:         StatusFlags
    let trace:          TraceFlags
    let batteryVolts:   Double
    let requestDate:    Bool

    var codeRunning: Bool { trace.contains(.robotCode) }

    // From tags
    var cpuUsage:       Double?
    var ramUsage:       Double?
    var diskUsage:      Double?
    var canUtilization: Double?
}

enum StatusPacket {
    static func parse(_ data: Data) -> RobotStatus? {
        guard data.count >= 8 else { return nil }

        let seq     = UInt16(data[0]) << 8 | UInt16(data[1])
        let status  = RobotStatus.StatusFlags(rawValue: data[3])
        let trace   = RobotStatus.TraceFlags(rawValue: data[4])
        let battery = Double(data[5]) + Double(data[6]) / 256.0
        let reqDate = data[7] != 0

        var result = RobotStatus(
            sequenceNumber: seq,
            status:         status,
            trace:          trace,
            batteryVolts:   battery,
            requestDate:    reqDate
        )

        parseTags(data: data, offset: 8, into: &result)
        return result
    }

    private static func parseTags(data: Data, offset: Int, into result: inout RobotStatus) {
        var i = offset
        while i + 1 < data.count {
            let size  = Int(data[i])
            let tagID = data[i + 1]
            let end   = i + 1 + size
            guard end <= data.count, size >= 1 else { break }
            let payload = data.subdata(in: (i + 2)..<end)
            i = end

            switch tagID {
            case 0x05: // CPU — one byte, percent
                if !payload.isEmpty { result.cpuUsage = Double(payload[0]) }
            case 0x06: // RAM — totalMB (u16) freeMB (u16)
                if payload.count >= 4 {
                    let total = UInt16(payload[0]) << 8 | UInt16(payload[1])
                    let free  = UInt16(payload[2]) << 8 | UInt16(payload[3])
                    if total > 0 { result.ramUsage = Double(total - free) / Double(total) * 100 }
                }
            case 0x04: // Disk — totalMB (u32) freeMB (u32)
                if payload.count >= 8 {
                    let total = UInt32(payload[0]) << 24 | UInt32(payload[1]) << 16
                              | UInt32(payload[2]) << 8  | UInt32(payload[3])
                    let free  = UInt32(payload[4]) << 24 | UInt32(payload[5]) << 16
                              | UInt32(payload[6]) << 8  | UInt32(payload[7])
                    if total > 0 { result.diskUsage = Double(total - free) / Double(total) * 100 }
                }
            case 0x0e: // CAN — utilization% (u8)
                if !payload.isEmpty { result.canUtilization = Double(payload[0]) }
            default:
                break
            }
        }
    }
}
