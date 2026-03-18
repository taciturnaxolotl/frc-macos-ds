import Foundation
import IOKit
import IOKit.hid
import Observation

// MARK: - Supporting types

/// Stable key for IOHIDDevice in dictionaries (devices are reference types but not Hashable).
private struct DeviceKey: Hashable {
    let ptr: UnsafeMutableRawPointer
    init(_ device: IOHIDDevice) {
        ptr = Unmanaged.passUnretained(device).toOpaque()
    }
}

private struct DeviceData {
    let name:      String
    let vendorID:  Int
    let productID: Int
    var axisElements:   [IOHIDElement] = []
    var buttonElements: [IOHIDElement] = []
    var povElements:    [IOHIDElement] = []
    var joystickState = JoystickState()
}

struct ConnectedDevice: Identifiable {
    let id:        UUID
    let name:      String
    let vendorID:  Int
    let productID: Int
}

// MARK: - HIDManager

@Observable
final class HIDManager {
    private var manager:        IOHIDManager?
    private var deviceData:     [DeviceKey: DeviceData]           = [:]
    private var deviceIDs:      [DeviceKey: UUID]                 = [:]
    private var cookieToDevice: [IOHIDElementCookie: DeviceKey]   = [:]

    var connectedDevices: [ConnectedDevice] = []

    var onDeviceAdded:   ((UUID, JoystickState) -> Void)?
    var onDeviceRemoved: ((UUID) -> Void)?
    var onStateChanged:  ((UUID, JoystickState) -> Void)?
    var onLog: ((String) -> Void)?

    private func log(_ text: String) { onLog?(text) }

    // MARK: - Start / Stop

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = mgr

        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey    as String: kHIDUsage_GD_Joystick],
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey    as String: kHIDUsage_GD_GamePad],
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey    as String: kHIDUsage_GD_MultiAxisController],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matching as CFArray)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, device in
            guard let ctx else { return }
            let hm = Unmanaged<HIDManager>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hm.deviceAdded(device) } }
        }, selfPtr)

        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, device in
            guard let ctx else { return }
            let hm = Unmanaged<HIDManager>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hm.deviceRemoved(device) } }
        }, selfPtr)

        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            let hm = Unmanaged<HIDManager>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hm.inputValue(value) } }
        }, selfPtr)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        log("HIDManager: started (open result: \(openResult == kIOReturnSuccess ? "OK" : "0x\(String(openResult, radix: 16))"))")
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        manager          = nil
        deviceData       = [:]
        deviceIDs        = [:]
        cookieToDevice   = [:]
        connectedDevices = []
    }

    func currentState(for id: UUID) -> JoystickState? {
        guard let key = deviceIDs.first(where: { $0.value == id })?.key else { return nil }
        return deviceData[key]?.joystickState
    }

    // MARK: - Device add / remove

    private func deviceAdded(_ device: IOHIDDevice) {
        let key = DeviceKey(device)
        guard deviceData[key] == nil else { return }

        let name      = IOHIDDeviceGetProperty(device, kIOHIDProductKey   as CFString) as? String ?? "Unknown Joystick"
        let vendorID  = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey  as CFString) as? Int) ?? 0
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0

        var data             = DeviceData(name: name, vendorID: vendorID, productID: productID)
        data.joystickState.name = name
        buildElementMap(device: device, key: key, into: &data)

        let id = UUID()
        deviceData[key] = data
        deviceIDs[key]  = id
        connectedDevices.append(ConnectedDevice(id: id, name: name, vendorID: vendorID, productID: productID))
        log("HIDManager: device added — \"\(name)\" vendor=0x\(String(vendorID, radix: 16)) product=0x\(String(productID, radix: 16)) axes=\(data.joystickState.axes.count) buttons=\(data.joystickState.buttons.count) povs=\(data.joystickState.povs.count)")
        onDeviceAdded?(id, data.joystickState)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let key = DeviceKey(device)
        guard let id = deviceIDs[key] else { return }
        // Clean up cookie map entries for this device
        cookieToDevice = cookieToDevice.filter { $0.value != key }
        deviceData.removeValue(forKey: key)
        deviceIDs.removeValue(forKey: key)
        connectedDevices.removeAll { $0.id == id }
        onDeviceRemoved?(id)
    }

    // MARK: - Element mapping

    private func buildElementMap(device: IOHIDDevice, key: DeviceKey, into data: inout DeviceData) {
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device, nil, IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return }

        var axes:    [(IOHIDElement, UInt32)] = []
        var buttons: [(IOHIDElement, UInt32)] = []
        var povs:    [IOHIDElement]           = []

        for el in elements {
            let page  = IOHIDElementGetUsagePage(el)
            let usage = IOHIDElementGetUsage(el)
            let type  = IOHIDElementGetType(el)
            let isInput = type == kIOHIDElementTypeInput_Axis
                       || type == kIOHIDElementTypeInput_Button
                       || type == kIOHIDElementTypeInput_Misc
            guard isInput else { continue }

            if page == UInt32(kHIDPage_GenericDesktop) {
                let hatswitch = UInt32(kHIDUsage_GD_Hatswitch)
                // All GD axis usages: X(0x30)…Wheel(0x38), plus Vx-Vz, Vbrx-Vbrz range
                let axisRange: ClosedRange<UInt32> = UInt32(kHIDUsage_GD_X)...UInt32(kHIDUsage_GD_Wheel)
                if usage == hatswitch {
                    povs.append(el)
                } else if axisRange.contains(usage) {
                    axes.append((el, usage))
                }
            } else if page == UInt32(kHIDPage_Button) {
                buttons.append((el, usage))
            }
        }

        axes.sort    { $0.1 < $1.1 }
        buttons.sort { $0.1 < $1.1 }

        data.axisElements   = axes.map(\.0)
        data.buttonElements = buttons.map(\.0)
        data.povElements    = povs

        data.joystickState.axes    = [Int8](repeating: 0,     count: min(axes.count,    12))
        data.joystickState.buttons = [Bool](repeating: false,  count: min(buttons.count, 32))
        data.joystickState.povs    = [Int16](repeating: -1,    count: min(povs.count,     4))

        // Map every element cookie to this device key so inputValue can look it up
        for el in elements {
            cookieToDevice[IOHIDElementGetCookie(el)] = key
        }
    }

    // MARK: - Input values

    private func inputValue(_ value: IOHIDValue) {
        let element  = IOHIDValueGetElement(value)
        let cookie   = IOHIDElementGetCookie(element)
        guard let key = cookieToDevice[cookie], var data = deviceData[key] else { return }

        let intValue = IOHIDValueGetIntegerValue(value)
        let page     = IOHIDElementGetUsagePage(element)

        if page == UInt32(kHIDPage_GenericDesktop) {
            if let idx = data.axisElements.firstIndex(where: { IOHIDElementGetCookie($0) == cookie }),
               idx < data.joystickState.axes.count {
                let lo = IOHIDElementGetLogicalMin(element)
                let hi = IOHIDElementGetLogicalMax(element)
                data.joystickState.axes[idx] = normalizeAxis(intValue, lo: lo, hi: hi)
            }
            if let idx = data.povElements.firstIndex(where: { IOHIDElementGetCookie($0) == cookie }),
               idx < data.joystickState.povs.count {
                let lo    = IOHIDElementGetLogicalMin(element)
                let hi    = IOHIDElementGetLogicalMax(element)
                let steps = hi - lo + 1
                if intValue < lo || intValue > hi || steps <= 0 {
                    data.joystickState.povs[idx] = -1
                } else {
                    data.joystickState.povs[idx] = Int16((intValue - lo) * 360 / steps)
                }
            }
        } else if page == UInt32(kHIDPage_Button) {
            if let idx = data.buttonElements.firstIndex(where: { IOHIDElementGetCookie($0) == cookie }),
               idx < data.joystickState.buttons.count {
                data.joystickState.buttons[idx] = intValue != 0
            }
        }

        let id = deviceIDs[key]
        deviceData[key] = data
        if let id { onStateChanged?(id, data.joystickState) }
    }

    // MARK: - Helpers

    private func normalizeAxis(_ value: CFIndex, lo: CFIndex, hi: CFIndex) -> Int8 {
        guard hi > lo else { return 0 }
        let normalized = Double(value - lo) / Double(hi - lo) * 255.0 - 128.0
        return Int8(max(-128, min(127, Int(normalized.rounded()))))
    }
}
