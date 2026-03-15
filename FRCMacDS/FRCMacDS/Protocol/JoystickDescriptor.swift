import Foundation

// Sent DS → Robot over TCP to describe a joystick in a slot
struct JoystickDescriptor {
    var joystickIndex: UInt8
    var isXbox:        Bool
    var type:          UInt8
    var name:          String
    var axisCount:     UInt8
    var axisTypes:     [UInt8]    // one per axis
    var buttonCount:   UInt8
    var povCount:      UInt8

    func encode() -> Data {
        var data = Data()
        data.append(joystickIndex)
        data.append(isXbox ? 1 : 0)
        data.append(type)

        // Name: 16 bytes, null-padded
        var nameBytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in Data(name.utf8).prefix(16).enumerated() { nameBytes[i] = b }
        data.append(contentsOf: nameBytes)

        data.append(axisCount)
        data.append(contentsOf: axisTypes.prefix(Int(axisCount)))
        data.append(buttonCount)
        data.append(povCount)
        return data
    }
}
