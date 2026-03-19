import Foundation
import Observation

/// Orchestrates all network communication with the robot.
@Observable
final class DSConnection {
    private let appState:    AppState
    private let udpSender  = UDPSender()
    private let udpReceiver = UDPReceiver()
    private let tcpChannel = TCPChannel()

    private var sequenceNumber: UInt16 = 0
    private var lastReceivedAt: ContinuousClock.Instant?
    private var watchdogTask:   Task<Void, Never>?

    private var sentDateTime:   Bool = false
    private var requestDateTime: Bool = false
    private var tcpTask:        Task<Void, Never>?

    var isConnected: Bool { appState.robotCommsOK }
    var onRumble: (() -> Void)?

    init(appState: AppState) {
        self.appState = appState
        wireCallbacks()
    }

    // MARK: - Lifecycle

    func connect() {
        let ip = appState.robotIP
        udpSender.start(host: ip)
        udpReceiver.start()
        tcpChannel.connect(to: ip)
        appState.connectionState = .connecting
        log("Connecting to \(ip)…")
        startWatchdog()
    }

    func disconnect() {
        udpSender.stop()
        udpReceiver.stop()
        tcpChannel.disconnect()
        watchdogTask?.cancel()
        watchdogTask    = nil
        tcpTask?.cancel()
        tcpTask         = nil
        sentDateTime    = false
        requestDateTime = false
        sequenceNumber  = 0
        lastReceivedAt  = nil

        appState.isEnabled       = false
        appState.robotCommsOK    = false
        appState.robotCodeOK     = false
        appState.connectionState = .disconnected
        log("Disconnected.")
    }

    // MARK: - Callbacks

    private func log(_ text: String, level: LogMessage.Level = .info) {
        appState.appendLog(LogMessage(timestamp: .now, level: level, text: text))
    }

    private func wireCallbacks() {
        let logFn: (String) -> Void = { [weak self] text in
            self?.log(text)
        }
        udpSender.onLog = logFn
        udpReceiver.onLog = logFn
        tcpChannel.onLog = logFn

        udpSender.onSendPacket = { [weak self] in
            self?.buildUDPPacket() ?? Data()
        }

        udpReceiver.onReceive = { [weak self] data in
            self?.handleRobotUDP(data)
        }

        tcpChannel.onMessage = { [weak self] tagID, payload in
            self?.handleTCPMessage(tagID: tagID, payload: payload)
        }

        tcpChannel.onConnected = { [weak self] in
            self?.appState.startNewSession()
            self?.startTCPLoop()
            self?.log("TCP connected.")
        }

        tcpChannel.onDisconnected = { [weak self] in
            self?.log("TCP disconnected.", level: .warning)
            self?.appState.saveCurrentSession()
        }
    }

    // MARK: - Outbound UDP

    private func buildUDPPacket() -> Data {
        sequenceNumber &+= 1

        var control = ControlByte()
        if appState.isEStopped { control.insert(.estop) }
        if appState.isEnabled  { control.insert(.enabled) }
        control.rawValue |= appState.mode.rawValue

        var request = RequestByte([.dsConnected])
        if appState.pendingReboot {
            request.insert(.rebootRoboRIO)
            appState.pendingReboot = false
        }
        if appState.pendingRestartCode {
            request.insert(.restartCode)
            appState.pendingRestartCode = false
        }

        let sendDT = !sentDateTime || requestDateTime
        if sendDT { sentDateTime = true; requestDateTime = false }

        // Only include joystick tags when enabled (per WPILib protocol)
        let joysticks: [JoystickTagData] = appState.isEnabled
            ? appState.joystickSlots.map { $0.state?.toTagData() ?? JoystickTagData.neutral }
            : []

        return PacketBuilder.build(
            sequence:     sequenceNumber,
            control:      control,
            request:      request,
            alliance:     appState.allianceStation,
            joysticks:    joysticks,
            sendDateTime: sendDT
        )
    }

    // MARK: - Inbound UDP

    private func handleRobotUDP(_ data: Data) {
        guard let status = StatusPacket.parse(data) else {
            log("StatusPacket parse failed, \(data.count) bytes: \(data.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))", level: .warning)
            return
        }

        lastReceivedAt = .now
        if !appState.robotCommsOK {
            log("UDP comms established (seq \(status.sequenceNumber), battery \(String(format: "%.1f", status.batteryVolts))V)")
        }
        appState.robotCommsOK    = true
        appState.robotCodeOK     = status.codeRunning
        appState.batteryVoltage  = status.batteryVolts

        if status.requestDate { requestDateTime = true }

        appState.batteryHistory.append(status.batteryVolts)
        if appState.batteryHistory.count > 300 { appState.batteryHistory.removeFirst() }

        if let v = status.cpuUsage      { appState.cpuUsage       = v }
        if let v = status.ramUsage      { appState.ramUsage       = v }
        if let v = status.diskUsage     { appState.diskUsage      = v }
        if let v = status.canUtilization { appState.canUtilization = v }

        // Pass rumble data to joystick slots
        if !status.rumble.isEmpty {
            for (i, rumble) in status.rumble.prefix(appState.joystickSlots.count).enumerated() {
                appState.joystickSlots[i].rumble = rumble
            }
            onRumble?()
        }

        appState.connectionState = appState.isEStopped ? .eStopped
                                 : appState.isEnabled  ? .enabled
                                 :                       .connected
    }

    // MARK: - Inbound TCP

    private func handleTCPMessage(tagID: UInt8, payload: Data) {
        switch tagID {
        case DSTag.stdout:
            // Bytes 0-3: float32 timestamp, bytes 4-5: sequence number, bytes 6+: message
            let textBytes = payload.count > 6 ? payload.dropFirst(6) : payload
            if let text = String(bytes: textBytes, encoding: .utf8) {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    log(clean, level: .print)
                }
            }
        case DSTag.errorMessage:
            // Bytes 0-3: timestamp, 4-5: seq, 6-7: reserved, 8-11: error code, 12: flags
            // Bytes 13+: 2-byte-length-prefixed strings: Details, Location, Call Stack
            guard payload.count >= 13 else { return }
            let isError = (payload[12] & 0x80) != 0
            let text = parseLengthPrefixedStrings(payload.dropFirst(13))
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            log(text, level: isError ? .error : .warning)
        default:
            break
        }
    }

    // MARK: - Helpers

    /// Parses a sequence of 2-byte-length-prefixed ASCII strings (OpenDS format)
    private func parseLengthPrefixedStrings(_ data: Data) -> [String] {
        var result: [String] = []
        var i = data.startIndex
        while i + 1 < data.endIndex {
            let len = Int(data[i]) << 8 | Int(data[i + 1])
            i += 2
            guard i + len <= data.endIndex else { break }
            let chunk = data[i..<(i + len)]
            let s = String(bytes: chunk, encoding: .utf8)?
                .filter { $0.asciiValue.map { $0 > 31 && $0 < 127 } ?? false }
            if let s, !s.isEmpty { result.append(s) }
            i += len
        }
        return result
    }

    // MARK: - TCP cycle

    private func startTCPLoop() {
        tcpTask?.cancel()
        tcpTask = Task { @MainActor [weak self] in
            let clock    = ContinuousClock()
            let interval = Duration.milliseconds(20)
            var next     = clock.now
            while !Task.isCancelled {
                self?.sendTCPCycle()
                next += interval
                try? await clock.sleep(until: next, tolerance: .milliseconds(2))
            }
        }
    }

    private func sendTCPCycle() {
        // Match info
        var matchInfo = Data()
        matchInfo.append(0x00)   // match number hi
        matchInfo.append(0x00)   // match number lo
        matchInfo.append(0x00)   // replay number
        matchInfo.append(0x00)   // match type: 0 = none/practice
        tcpChannel.send(tagID: DSTag.matchInfo, payload: matchInfo)

        // Joystick descriptors — all 6 slots, placeholder for empty
        for i in 0..<appState.joystickSlots.count {
            let slot = appState.joystickSlots[i]
            let desc = slot.state?.toDescriptor(index: UInt8(i))
                ?? JoystickDescriptor(joystickIndex: UInt8(i), isXbox: false, type: 0,
                                      name: "", axisCount: 0, axisTypes: [],
                                      buttonCount: 0, povCount: 0)
            tcpChannel.send(tagID: DSTag.joystickDesc, payload: desc.encode())
        }

        // Game data (empty)
        tcpChannel.send(tagID: DSTag.gameData, payload: Data())

        // DS ping
        tcpChannel.send(tagID: DSTag.dsPing, payload: Data())
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                try? await clock.sleep(for: .milliseconds(100))
                guard let self, let last = self.lastReceivedAt else { continue }
                if clock.now - last > .milliseconds(500) && self.appState.robotCommsOK {
                    self.log("UDP watchdog: no response for 500ms, marking disconnected", level: .warning)
                    self.appState.robotCommsOK    = false
                    self.appState.robotCodeOK     = false
                    self.appState.isEnabled       = false
                    if self.appState.connectionState != .disconnected {
                        self.appState.connectionState = .connecting
                    }
                }
            }
        }
    }
}
