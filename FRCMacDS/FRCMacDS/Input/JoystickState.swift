import Foundation

struct JoystickState {
    var axes:    [Int8]  = []      // -128…127
    var buttons: [Bool]  = []
    var povs:    [Int16] = []      // degrees 0–359, or -1 if unpressed
    var name:    String  = ""
    var isXbox:  Bool    = false
    var type:    UInt8   = 20      // kHIDUsage_GD_Joystick

    func toTagData() -> JoystickTagData {
        JoystickTagData(axes: axes, buttons: buttons, povs: povs)
    }

    func toDescriptor(index: UInt8) -> JoystickDescriptor {
        JoystickDescriptor(
            joystickIndex: index,
            isXbox:        isXbox,
            type:          type,
            name:          name,
            axisCount:     UInt8(min(axes.count, 12)),
            axisTypes:     [UInt8](repeating: 0, count: min(axes.count, 12)),
            buttonCount:   UInt8(min(buttons.count, 32)),
            povCount:      UInt8(min(povs.count, 4))
        )
    }
}
