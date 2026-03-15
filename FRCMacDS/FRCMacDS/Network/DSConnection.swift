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

    var isConnected: Bool { appState.robotCommsOK }

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
        appState.appendLog(LogMessage(timestamp: .now, level: .info, text: "Connecting to \(ip)…"))
        startWatchdog()
    }

    func disconnect() {
        udpSender.stop()
        udpReceiver.stop()
        tcpChannel.disconnect()
        watchdogTask?.cancel()
        watchdogTask    = nil
        sentDateTime    = false
        requestDateTime = false
        sequenceNumber  = 0
        lastReceivedAt  = nil

        appState.isEnabled       = false
        appState.robotCommsOK    = false
        appState.robotCodeOK     = false
        appState.connectionState = .disconnected
        appState.appendLog(LogMessage(timestamp: .now, level: .info, text: "Disconnected."))
    }

    // MARK: - Callbacks

    private func wireCallbacks() {
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
            self?.sendDescriptors()
            self?.appState.appendLog(LogMessage(timestamp: .now, level: .info, text: "TCP connected."))
        }

        tcpChannel.onDisconnected = { [weak self] in
            self?.appState.appendLog(LogMessage(timestamp: .now, level: .warning, text: "TCP disconnected."))
        }
    }

    // MARK: - Outbound UDP

    private func buildUDPPacket() -> Data {
        sequenceNumber &+= 1

        var control = ControlByte()
        if appState.isEStopped { control.insert(.estop) }
        if appState.isEnabled  { control.insert(.enabled) }
        control.rawValue |= appState.mode.rawValue

        var request = RequestByte()
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

        let joysticks = appState.joystickSlots.map {
            $0.state?.toTagData() ?? JoystickTagData.neutral
        }

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
        guard let status = StatusPacket.parse(data) else { return }

        lastReceivedAt           = .now
        appState.robotCommsOK    = true
        appState.robotCodeOK     = status.status.contains(.codeInit)
        appState.batteryVoltage  = status.batteryVolts

        if status.requestDate { requestDateTime = true }

        appState.batteryHistory.append(status.batteryVolts)
        if appState.batteryHistory.count > 300 { appState.batteryHistory.removeFirst() }

        if let v = status.cpuUsage      { appState.cpuUsage       = v }
        if let v = status.ramUsage      { appState.ramUsage       = v }
        if let v = status.diskUsage     { appState.diskUsage      = v }
        if let v = status.canUtilization { appState.canUtilization = v }

        appState.connectionState = appState.isEStopped ? .eStopped
                                 : appState.isEnabled  ? .enabled
                                 :                       .connected
    }

    // MARK: - Inbound TCP

    private func handleTCPMessage(tagID: UInt8, payload: Data) {
        switch tagID {
        case DSTag.stdout:
            if let text = String(bytes: payload, encoding: .utf8) {
                appState.appendLog(LogMessage(timestamp: .now, level: .print, text: text.trimmingCharacters(in: .newlines)))
            }
        case DSTag.errorMessage:
            guard payload.count >= 9 else { return }
            let isError  = payload[0] != 0
            let msgStart = min(9, payload.count)
            if let text = String(bytes: payload[msgStart...], encoding: .utf8) {
                appState.appendLog(LogMessage(timestamp: .now, level: isError ? .error : .warning, text: text))
            }
        default:
            break
        }
    }

    // MARK: - TCP descriptors

    private func sendDescriptors() {
        for (i, slot) in appState.joystickSlots.enumerated() {
            guard let state = slot.state else { continue }
            let desc = state.toDescriptor(index: UInt8(i))
            tcpChannel.send(tagID: DSTag.joystickDesc, payload: desc.encode())
        }
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
