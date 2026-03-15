import Foundation
import Observation

@Observable
final class AppState {

    // MARK: - Configuration

    var teamNumber: Int {
        didSet { UserDefaults.standard.set(teamNumber, forKey: "teamNumber") }
    }
    var allianceStation: AllianceStation = .red1
    var gameData: String = ""

    // MARK: - Control

    var isEnabled: Bool = false {
        didSet {
            if isEnabled, !oldValue { enabledAt = Date() }
            else if !isEnabled      { enabledAt = nil }
        }
    }
    var isEStopped:  Bool      = false
    var mode:        RobotMode = .teleop
    var enabledAt:   Date?     = nil

    // MARK: - Connection state

    var connectionState: ConnectionState = .disconnected
    var robotCommsOK:    Bool = false
    var robotCodeOK:     Bool = false

    // MARK: - Telemetry

    var batteryVoltage:  Double = 0.0
    var batteryHistory:  [Double] = []
    var cpuUsage:        Double = 0.0
    var ramUsage:        Double = 0.0
    var diskUsage:       Double = 0.0
    var canUtilization:  Double = 0.0
    var tripTimeMs:      Int    = 0
    var packetLoss:      Double = 0.0

    // MARK: - Joysticks (6 slots)

    var joystickSlots: [JoystickSlot] = Array(repeating: .empty, count: 6)

    var joysticksOK: Bool {
        joystickSlots.contains { $0.state != nil }
    }

    // MARK: - Log

    var logMessages: [LogMessage] = []

    // MARK: - Pending one-shot requests

    var pendingReboot:      Bool = false
    var pendingRestartCode: Bool = false

    // MARK: - Derived

    var robotIP: String {
        "10.\(teamNumber / 100).\(teamNumber % 100).2"
    }

    // MARK: - Init

    init() {
        teamNumber = UserDefaults.standard.integer(forKey: "teamNumber")
    }

    // MARK: - Helpers

    func appendLog(_ msg: LogMessage) {
        logMessages.append(msg)
        if logMessages.count > 2000 {
            logMessages.removeFirst(logMessages.count - 2000)
        }
    }
}

// MARK: - Supporting types

struct JoystickSlot {
    var deviceID: UUID?
    var state:    JoystickState?

    static let empty = JoystickSlot()
}

struct LogMessage: Identifiable {
    enum Level { case info, warning, error, print }
    let id        = UUID()
    let timestamp: Date
    let level:     Level
    let text:      String
}
