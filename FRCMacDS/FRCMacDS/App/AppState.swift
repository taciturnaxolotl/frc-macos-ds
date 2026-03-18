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
    var currentSessionID: UUID?
    private var currentSessionStart: Date?

    // Saved session browsing
    var savedSessions: [LogSession] = []
    var viewingSessionID: UUID? = nil  // nil = live

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

    /// Call when TCP connects to start a new log session
    func startNewSession() {
        saveCurrentSession()
        let id = UUID()
        currentSessionID = id
        currentSessionStart = Date()
        logMessages.removeAll()
        appendLog(LogMessage(timestamp: .now, level: .info, text: "Session started."))
    }

    /// Save current session to disk
    func saveCurrentSession() {
        guard let id = currentSessionID, let start = currentSessionStart, !logMessages.isEmpty else { return }
        let session = LogSession(
            id: id,
            startDate: start,
            teamNumber: teamNumber,
            messages: logMessages.map { SavedLogMessage($0) }
        )
        LogStore.shared.save(session)
        refreshSavedSessions()
    }

    func refreshSavedSessions() {
        savedSessions = LogStore.shared.listSessions()
    }
}

// MARK: - Supporting types

struct JoystickSlot {
    var deviceID: UUID?
    var state:    JoystickState?
    var rumble:   JoystickRumble = JoystickRumble()

    static let empty = JoystickSlot()
}

struct LogMessage: Identifiable {
    enum Level { case info, warning, error, print }
    let id        = UUID()
    let timestamp: Date
    let level:     Level
    let text:      String
}
