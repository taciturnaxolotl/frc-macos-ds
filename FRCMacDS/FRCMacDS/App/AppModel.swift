import Foundation

/// Root model that owns and wires together all subsystems.
final class AppModel {
    let appState:       AppState
    let hidManager:     HIDManager
    let connection:     DSConnection
    let pcDiag:         PCDiagnosticsMonitor
    let keybindManager: KeybindManager

    init() {
        let state = AppState()
        appState       = state
        hidManager     = HIDManager()
        connection     = DSConnection(appState: state)
        pcDiag         = PCDiagnosticsMonitor()
        keybindManager = KeybindManager()

        hidManager.onDeviceAdded = { [weak self] (id: UUID, state: JoystickState) in
            guard let self else { return }
            // Don't auto-assign if already in a slot
            guard !self.appState.joystickSlots.contains(where: { $0.deviceID == id }) else { return }
            if let emptyIdx = self.appState.joystickSlots.firstIndex(where: { $0.deviceID == nil }) {
                self.appState.joystickSlots[emptyIdx] = JoystickSlot(deviceID: id, state: state)
            }
        }

        hidManager.onDeviceRemoved = { [weak self] (id: UUID) in
            guard let self else { return }
            if let idx = self.appState.joystickSlots.firstIndex(where: { $0.deviceID == id }) {
                self.appState.joystickSlots[idx] = .empty
            }
        }

        hidManager.onStateChanged = { [weak self] (id: UUID, state: JoystickState) in
            guard let self else { return }
            if let idx = self.appState.joystickSlots.firstIndex(where: { $0.deviceID == id }) {
                self.appState.joystickSlots[idx].state = state
            }
        }

        hidManager.start()
        pcDiag.start()
    }
}
