import Foundation

// Robot → DS UDP packet (sent from RoboRIO to DS on port 1150)
struct RobotStatus {
    struct Flags: OptionSet {
        var rawValue: UInt8
        static let estop    = Flags(rawValue: 1 << 7)
        static let brownout = Flags(rawValue: 1 << 4)
        static let codeInit = Flags(rawValue: 1 << 3)  // WPILib initialized
        static let enabled  = Flags(rawValue: 1 << 2)
    }

    let sequenceNumber: UInt16
    let status:         Flags
    let mode:           UInt8      // bits 1-0
    let batteryVolts:   Double
    let requestDate:    Bool

    // From tags
    var cpuUsage:       Double?
    var ramUsage:       Double?    // percent
    var diskUsage:      Double?    // percent
    var canUtilization: Double?    // percent
}

enum StatusPacket {
    static func parse(_ data: Data) -> RobotStatus? {
        guard data.count >= 8 else { return nil }

        let seq     = UInt16(data[0]) << 8 | UInt16(data[1])
        // data[2] = comm version (0x01)
        let status  = RobotStatus.Flags(rawValue: data[3])
        // data[4] = trace byte
        let battery = Double(data[5]) + Double(data[6]) / 256.0
        let reqDate = data[7] != 0

        var result = RobotStatus(
            sequenceNumber: seq,
            status:         status,
            mode:           data[3] & 0x03,
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
            case 0x05: // CPU info — one byte, percent
                if !payload.isEmpty {
                    result.cpuUsage = Double(payload[0])
                }
            case 0x06: // RAM info — totalMB (u16) freeMB (u16)
                if payload.count >= 4 {
                    let total = UInt16(payload[0]) << 8 | UInt16(payload[1])
                    let free  = UInt16(payload[2]) << 8 | UInt16(payload[3])
                    if total > 0 {
                        result.ramUsage = Double(total - free) / Double(total) * 100.0
                    }
                }
            case 0x04: // Disk info — totalMB (u32) freeMB (u32)
                if payload.count >= 8 {
                    let total = UInt32(payload[0]) << 24 | UInt32(payload[1]) << 16
                              | UInt32(payload[2]) << 8  | UInt32(payload[3])
                    let free  = UInt32(payload[4]) << 24 | UInt32(payload[5]) << 16
                              | UInt32(payload[6]) << 8  | UInt32(payload[7])
                    if total > 0 {
                        result.diskUsage = Double(total - free) / Double(total) * 100.0
                    }
                }
            case 0x0e: // CAN metrics — utilization% (u8) ...
                if !payload.isEmpty {
                    result.canUtilization = Double(payload[0])
                }
            default:
                break
            }
        }
    }
}
