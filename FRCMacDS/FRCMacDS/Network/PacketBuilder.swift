import Foundation

enum PacketBuilder {
    /// Build a DS → Robot UDP control packet (sent at 50 Hz).
    static func build(
        sequence:     UInt16,
        control:      ControlByte,
        request:      RequestByte,
        alliance:     AllianceStation,
        joysticks:    [JoystickTagData],
        sendDateTime: Bool
    ) -> Data {
        var data = Data()

        // Header (6 bytes)
        data.append(UInt8(sequence >> 8))
        data.append(UInt8(sequence & 0xFF))
        data.append(0x01)               // comm version
        data.append(control.rawValue)
        data.append(request.rawValue)
        data.append(alliance.rawValue)

        // Optional date/time tags (sent once and on request)
        if sendDateTime {
            data.append(contentsOf: encodeDateTimeTag())
            data.append(contentsOf: encodeTimezoneTag())
        }

        // Joystick tags (one per slot, always 6)
        for joystick in joysticks {
            data.append(contentsOf: encodeTag(id: DSTag.joystick, payload: joystick.encode()))
        }

        return data
    }
}
