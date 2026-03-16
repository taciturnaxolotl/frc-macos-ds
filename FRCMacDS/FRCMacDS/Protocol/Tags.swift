import Foundation

// MARK: - Tag IDs

enum DSTag {
    // DS → Robot
    static let countdown: UInt8 = 0x07
    static let joystick:  UInt8 = 0x0c
    static let dateTime:  UInt8 = 0x0f
    static let timezone:  UInt8 = 0x10

    // DS → Robot (TCP)
    static let matchInfo:    UInt8 = 0x07
    static let dsPing:       UInt8 = 0x1D

    // Robot → DS (TCP)
    static let joystickDesc: UInt8 = 0x02
    static let gameData:     UInt8 = 0x0e
    static let errorMessage: UInt8 = 0x0b
    static let stdout:       UInt8 = 0x0c
}

// MARK: - Tag encoding

func encodeTag(id: UInt8, payload: Data) -> Data {
    var out = Data()
    out.append(UInt8(payload.count + 1))  // size includes id byte
    out.append(id)
    out.append(payload)
    return out
}

func encodeDateTimeTag() -> Data {
    let now   = Date()
    let cal   = Calendar.current
    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
    let us    = UInt32(now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) * 1_000_000)

    var payload = Data()
    payload.append(UInt8((us >> 24) & 0xFF))
    payload.append(UInt8((us >> 16) & 0xFF))
    payload.append(UInt8((us >>  8) & 0xFF))
    payload.append(UInt8( us        & 0xFF))
    payload.append(UInt8(comps.second ?? 0))
    payload.append(UInt8(comps.minute ?? 0))
    payload.append(UInt8(comps.hour   ?? 0))
    payload.append(UInt8(comps.day    ?? 1))
    payload.append(UInt8((comps.month ?? 1) - 1))  // protocol is 0-indexed
    payload.append(UInt8((comps.year ?? 1900) - 1900))
    return encodeTag(id: DSTag.dateTime, payload: payload)
}

func encodeTimezoneTag() -> Data {
    let tzData = Data(TimeZone.current.identifier.utf8)
    return encodeTag(id: DSTag.timezone, payload: tzData)
}

// MARK: - Joystick tag data

struct JoystickTagData {
    var axes:    [Int8]
    var buttons: [Bool]
    var povs:    [Int16]

    func encode() -> Data {
        var data = Data()

        // Axes
        data.append(UInt8(axes.count))
        for a in axes { data.append(UInt8(bitPattern: a)) }

        // Buttons (packed LSB-first per byte, then reversed)
        data.append(UInt8(buttons.count))
        let byteCount = (buttons.count + 7) / 8
        var btnBytes = [UInt8](repeating: 0, count: byteCount)
        for (i, b) in buttons.enumerated() where b {
            btnBytes[i / 8] |= 1 << (i % 8)
        }
        data.append(contentsOf: btnBytes.reversed())

        // POVs
        data.append(UInt8(povs.count))
        for p in povs {
            data.append(UInt8(truncatingIfNeeded: p >> 8))
            data.append(UInt8(truncatingIfNeeded: p))
        }
        return data
    }

    static let neutral = JoystickTagData(axes: [], buttons: [], povs: [])
}
