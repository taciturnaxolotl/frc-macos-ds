import Foundation

/// Root model that owns and wires together all subsystems.
final class AppModel {
    let appState:       AppState
    let hidManager:     HIDManager
    let gcManager:      GCManager
    let xboxUSBManager: XboxUSBManager
    let connection:     DSConnection
    let pcDiag:         PCDiagnosticsMonitor
    let keybindManager: KeybindManager
    private var rumbleTask: Task<Void, Never>?

    init() {
        let state = AppState()
        appState       = state
        hidManager     = HIDManager()
        gcManager      = GCManager()
        xboxUSBManager = XboxUSBManager()
        connection     = DSConnection(appState: state)
        pcDiag         = PCDiagnosticsMonitor()
        keybindManager = KeybindManager()

        wireInputManager(hidManager)
        wireInputManager(gcManager)
        wireInputManager(xboxUSBManager)
        let logFn: (String) -> Void = { [weak state] text in
            state?.appendLog(LogMessage(timestamp: .now, level: .info, text: text))
        }
        hidManager.onLog = logFn
        gcManager.onLog = logFn
        xboxUSBManager.onLog = logFn

        hidManager.start()
        gcManager.start()
        xboxUSBManager.start()
        pcDiag.start()
        startRumbleLoop()
    }

    /// Polls rumble values from appState and forwards to Xbox USB controllers.
    private func startRumbleLoop() {
        rumbleTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                try? await clock.sleep(for: .milliseconds(20))
                guard let self else { return }
                for slot in self.appState.joystickSlots {
                    guard let id = slot.deviceID else { continue }
                    let r = slot.rumble
                    if r.left > 0 || r.right > 0 {
                        self.xboxUSBManager.setRumble(deviceID: id, left: r.left, right: r.right)
                    }
                }
            }
        }
    }

    /// Wires onDeviceAdded/Removed/StateChanged for any input manager.
    private func wireInputManager<T>(_ mgr: T)
    where T: AnyObject & _InputManagerCallbacks {
        mgr.onDeviceAdded = { [weak self] (id: UUID, state: JoystickState) in
            guard let self else { return }
            guard !self.appState.joystickSlots.contains(where: { $0.deviceID == id }) else { return }
            if let emptyIdx = self.appState.joystickSlots.firstIndex(where: { $0.deviceID == nil }) {
                self.appState.joystickSlots[emptyIdx] = JoystickSlot(deviceID: id, state: state)
            }
        }
        mgr.onDeviceRemoved = { [weak self] (id: UUID) in
            guard let self else { return }
            if let idx = self.appState.joystickSlots.firstIndex(where: { $0.deviceID == id }) {
                self.appState.joystickSlots[idx] = .empty
            }
        }
        mgr.onStateChanged = { [weak self] (id: UUID, state: JoystickState) in
            guard let self else { return }
            if let idx = self.appState.joystickSlots.firstIndex(where: { $0.deviceID == id }) {
                self.appState.joystickSlots[idx].state = state
            }
        }
    }
}

/// Shared callback shape for input managers (HIDManager & GCManager).
protocol _InputManagerCallbacks: AnyObject {
    var onDeviceAdded:   ((UUID, JoystickState) -> Void)? { get set }
    var onDeviceRemoved: ((UUID) -> Void)? { get set }
    var onStateChanged:  ((UUID, JoystickState) -> Void)? { get set }
}

extension HIDManager: _InputManagerCallbacks {}
extension GCManager: _InputManagerCallbacks {}
extension XboxUSBManager: _InputManagerCallbacks {}
