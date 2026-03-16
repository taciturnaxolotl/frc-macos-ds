import Foundation

struct ControlByte: OptionSet {
    var rawValue: UInt8
    static let estop        = ControlByte(rawValue: 1 << 7)
    static let fmsConnected = ControlByte(rawValue: 1 << 3)
    static let enabled      = ControlByte(rawValue: 1 << 2)
}

struct RequestByte: OptionSet {
    var rawValue: UInt8
    static let dsConnected   = RequestByte(rawValue: 1 << 4)  // always set
    static let rebootRoboRIO = RequestByte(rawValue: 1 << 3)
    static let restartCode   = RequestByte(rawValue: 1 << 2)
}
