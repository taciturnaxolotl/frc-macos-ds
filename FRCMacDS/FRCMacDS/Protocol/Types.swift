import Foundation

enum RobotMode: UInt8, CaseIterable, Identifiable {
    case teleop = 0b00
    case test   = 0b01
    case auto   = 0b10

    var id: RawValue { rawValue }
    var label: String {
        switch self {
        case .teleop: "Teleoperated"
        case .test:   "Test"
        case .auto:   "Autonomous"
        }
    }
}

enum AllianceStation: UInt8, CaseIterable, Identifiable {
    case red1 = 0, red2, red3
    case blue1 = 3, blue2, blue3

    var id: RawValue { rawValue }
    var label: String {
        switch self {
        case .red1:  "Red 1"
        case .red2:  "Red 2"
        case .red3:  "Red 3"
        case .blue1: "Blue 1"
        case .blue2: "Blue 2"
        case .blue3: "Blue 3"
        }
    }
    var isRed: Bool { rawValue < 3 }
}

enum ConnectionState {
    case disconnected, connecting, connected, enabled, eStopped

    var label: String {
        switch self {
        case .disconnected: "No Robot Comms"
        case .connecting:   "Connecting…"
        case .connected:    "Connected"
        case .enabled:      "Enabled"
        case .eStopped:     "E-STOPPED"
        }
    }
}
