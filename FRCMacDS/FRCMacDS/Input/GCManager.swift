import Foundation
import GameController
import Observation

/// Discovers controllers via the GameController framework (Xbox, PS, MFi, etc.)
/// and maps their inputs to JoystickState for the DS slot system.
@Observable
final class GCManager {
    private var controllerIDs: [GCController: UUID] = [:]
    private var pollTask: Task<Void, Never>?

    var onDeviceAdded:   ((UUID, JoystickState) -> Void)?
    var onDeviceRemoved: ((UUID) -> Void)?
    var onStateChanged:  ((UUID, JoystickState) -> Void)?
    var onLog: ((String) -> Void)?

    private func log(_ text: String) { onLog?(text) }

    func start() {
        // Required for non-game apps to receive controller events
        GCController.shouldMonitorBackgroundEvents = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerConnected),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect, object: nil)

        // Pick up any already-connected controllers
        let existing = GCController.controllers()
        log("GCManager: started, \(existing.count) controller(s) already connected")
        for controller in existing {
            addController(controller)
        }

        // Poll state at 50 Hz to match DS packet rate
        pollTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let interval = Duration.milliseconds(20)
            var next = clock.now
            while !Task.isCancelled {
                self?.pollAll()
                next += interval
                try? await clock.sleep(until: next, tolerance: .milliseconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        NotificationCenter.default.removeObserver(self)
        controllerIDs.removeAll()
    }

    // MARK: - Connect / Disconnect

    @objc private func controllerConnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.addController(controller) } }
    }

    @objc private func controllerDisconnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.removeController(controller) } }
    }

    private func addController(_ controller: GCController) {
        guard controllerIDs[controller] == nil else { return }
        let id = UUID()
        controllerIDs[controller] = id
        let name = controller.vendorName ?? "Unknown"
        let category = controller.productCategory
        let hasExtended = controller.extendedGamepad != nil
        log("GCManager: controller added — \"\(name)\" category=\(category) extended=\(hasExtended)")
        let state = readState(controller)
        onDeviceAdded?(id, state)
    }

    private func removeController(_ controller: GCController) {
        guard let id = controllerIDs.removeValue(forKey: controller) else { return }
        log("GCManager: controller removed — \(controller.vendorName ?? "Unknown")")
        onDeviceRemoved?(id)
    }

    // MARK: - Polling

    private func pollAll() {
        for (controller, id) in controllerIDs {
            let state = readState(controller)
            onStateChanged?(id, state)
        }
    }

    // MARK: - State reading

    private func readState(_ controller: GCController) -> JoystickState {
        let name = controller.vendorName ?? "Controller"
        let isXbox = controller.extendedGamepad != nil
            && (name.localizedCaseInsensitiveContains("xbox")
                || controller.productCategory == "Xbox")

        if let gp = controller.extendedGamepad {
            return readExtended(gp, name: name, isXbox: isXbox)
        }
        return JoystickState(name: name)
    }

    private func readExtended(_ gp: GCExtendedGamepad, name: String, isXbox: Bool) -> JoystickState {
        // Axis layout matches WPILib XboxController:
        // 0: Left X, 1: Left Y, 2: Left Trigger, 3: Right Trigger, 4: Right X, 5: Right Y
        let axes: [Int8] = [
            floatToAxis(gp.leftThumbstick.xAxis.value),
            floatToAxis(-gp.leftThumbstick.yAxis.value),  // inverted: up = negative
            triggerToAxis(gp.leftTrigger.value),
            triggerToAxis(gp.rightTrigger.value),
            floatToAxis(gp.rightThumbstick.xAxis.value),
            floatToAxis(-gp.rightThumbstick.yAxis.value), // inverted: up = negative
        ]

        // Button layout matches WPILib XboxController:
        // 0:A  1:B  2:X  3:Y  4:LB  5:RB  6:Back  7:Start  8:L3  9:R3
        let buttons: [Bool] = [
            gp.buttonA.isPressed,
            gp.buttonB.isPressed,
            gp.buttonX.isPressed,
            gp.buttonY.isPressed,
            gp.leftShoulder.isPressed,
            gp.rightShoulder.isPressed,
            gp.buttonOptions?.isPressed ?? false,
            gp.buttonMenu.isPressed,
            gp.leftThumbstickButton?.isPressed ?? false,
            gp.rightThumbstickButton?.isPressed ?? false,
        ]

        // POV from dpad
        let pov = dpadToPOV(gp.dpad)

        return JoystickState(
            axes: axes, buttons: buttons, povs: [pov],
            name: name, isXbox: isXbox, type: 1  // kHIDUsage_GD_GamePad
        )
    }

    // MARK: - Helpers

    /// Map -1…1 float to -128…127 Int8
    private func floatToAxis(_ v: Float) -> Int8 {
        Int8(max(-128, min(127, Int((v * 128).rounded()))))
    }

    /// Map 0…1 trigger to -128…127 (WPILib convention: -128 = released, 127 = fully pressed)
    private func triggerToAxis(_ v: Float) -> Int8 {
        Int8(max(-128, min(127, Int((v * 255 - 128).rounded()))))
    }

    private func dpadToPOV(_ dpad: GCControllerDirectionPad) -> Int16 {
        let u = dpad.up.isPressed
        let d = dpad.down.isPressed
        let l = dpad.left.isPressed
        let r = dpad.right.isPressed
        switch (u, d, l, r) {
        case (true,  false, false, false): return 0
        case (true,  false, false, true):  return 45
        case (false, false, false, true):  return 90
        case (false, true,  false, true):  return 135
        case (false, true,  false, false): return 180
        case (false, true,  true,  false): return 225
        case (false, false, true,  false): return 270
        case (true,  false, true,  false): return 315
        default:                           return -1
        }
    }
}
