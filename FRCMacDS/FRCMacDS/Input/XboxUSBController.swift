import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

// Bridged UUID constants (C externs aren't visible to Swift)
private let kUSBDeviceUserClientTypeID  = USBBridge_kIOUSBDeviceUserClientTypeID()!.takeUnretainedValue()
private let kCFPlugInInterfaceID        = USBBridge_kIOCFPlugInInterfaceID()!.takeUnretainedValue()
private let kUSBDeviceInterfaceID       = USBBridge_kIOUSBDeviceInterfaceID()!.takeUnretainedValue()
private let kUSBInterfaceUserClientID   = USBBridge_kIOUSBInterfaceUserClientTypeID()!.takeUnretainedValue()
private let kUSBInterfaceInterfaceID    = USBBridge_kIOUSBInterfaceInterfaceID()!.takeUnretainedValue()

// MARK: - XInput report parsing

/// Raw 20-byte XInput input report layout (Xbox 360 / compatible controllers)
private struct XInputReport {
    // Byte 0: message type (0x00)
    // Byte 1: packet size (0x14 = 20)
    // Bytes 2-3: button bitmask
    // Byte 4: left trigger (0-255)
    // Byte 5: right trigger (0-255)
    // Bytes 6-7: left stick X (int16 LE)
    // Bytes 8-9: left stick Y (int16 LE)
    // Bytes 10-11: right stick X (int16 LE)
    // Bytes 12-13: right stick Y (int16 LE)

    static func parse(_ data: UnsafeBufferPointer<UInt8>, into state: inout JoystickState) -> Bool {
        guard data.count >= 14 else { return false }

        let btnLo = data[2]
        let btnHi = data[3]

        // DPad → POV (byte 2 bits 0-3)
        let up    = btnLo & 0x01 != 0
        let down  = btnLo & 0x02 != 0
        let left  = btnLo & 0x04 != 0
        let right = btnLo & 0x08 != 0
        let pov   = dpadToPOV(up: up, down: down, left: left, right: right)

        // Buttons mapped to WPILib XboxController order:
        // 0:A  1:B  2:X  3:Y  4:LB  5:RB  6:Back  7:Start  8:L3  9:R3
        let buttons: [Bool] = [
            btnHi & 0x10 != 0,  // A
            btnHi & 0x20 != 0,  // B
            btnHi & 0x40 != 0,  // X
            btnHi & 0x80 != 0,  // Y
            btnHi & 0x01 != 0,  // LB
            btnHi & 0x02 != 0,  // RB
            btnLo & 0x20 != 0,  // Back
            btnLo & 0x10 != 0,  // Start
            btnLo & 0x40 != 0,  // L3
            btnLo & 0x80 != 0,  // R3
        ]

        // Triggers (0-255 → -128..127 for WPILib)
        let lt = Int8(clamping: Int(data[4]) - 128)
        let rt = Int8(clamping: Int(data[5]) - 128)

        // Sticks (int16 LE, -32768..32767 → -128..127)
        let lx = stickToAxis(lo: data[6],  hi: data[7])
        let ly = stickToAxis(lo: data[8],  hi: data[9],  invert: true)
        let rx = stickToAxis(lo: data[10], hi: data[11])
        let ry = stickToAxis(lo: data[12], hi: data[13], invert: true)

        state.axes    = [lx, ly, lt, rt, rx, ry]
        state.buttons = buttons
        state.povs    = [pov]
        return true
    }
}

/// GIP (Game Input Protocol) report — Xbox One / Series X controllers
private struct GIPReport {
    // Byte 0: 0x20 (input command)
    // Byte 1: client (0x00)
    // Byte 2: sequence
    // Byte 3: remaining length
    // Byte 4: face/menu buttons — Sync(0), ?(1), Menu(2), View(3), A(4), B(5), X(6), Y(7)
    // Byte 5: dpad/shoulder/stick — Up(0), Down(1), Left(2), Right(3), LB(4), RB(5), L3(6), R3(7)
    // Byte 6-7: left trigger (uint16 LE, 0-1023)
    // Byte 8-9: right trigger (uint16 LE, 0-1023)
    // Byte 10-11: left stick X (int16 LE)
    // Byte 12-13: left stick Y (int16 LE)
    // Byte 14-15: right stick X (int16 LE)
    // Byte 16-17: right stick Y (int16 LE)

    static func parse(_ data: UnsafeBufferPointer<UInt8>, into state: inout JoystickState) -> Bool {
        guard data.count >= 18, data[0] == 0x20 else { return false }

        let face = data[4]   // A/B/X/Y, Menu, View
        let phys = data[5]   // DPad, LB/RB, L3/R3

        // DPad (byte 5 bits 0-3)
        let up    = phys & 0x01 != 0
        let down  = phys & 0x02 != 0
        let left  = phys & 0x04 != 0
        let right = phys & 0x08 != 0
        let pov   = dpadToPOV(up: up, down: down, left: left, right: right)

        // Buttons → WPILib XboxController order
        let buttons: [Bool] = [
            face & 0x10 != 0,  // A
            face & 0x20 != 0,  // B
            face & 0x40 != 0,  // X
            face & 0x80 != 0,  // Y
            phys & 0x10 != 0,  // LB
            phys & 0x20 != 0,  // RB
            face & 0x08 != 0,  // Back/View
            face & 0x04 != 0,  // Start/Menu
            phys & 0x40 != 0,  // L3
            phys & 0x80 != 0,  // R3
        ]

        // Triggers (uint16 LE 0-1023 → -128..127)
        let ltRaw = UInt16(data[6]) | UInt16(data[7]) << 8
        let rtRaw = UInt16(data[8]) | UInt16(data[9]) << 8
        let lt = Int8(clamping: Int(ltRaw) * 255 / 1023 - 128)
        let rt = Int8(clamping: Int(rtRaw) * 255 / 1023 - 128)

        // Sticks (int16 LE)
        let lx = stickToAxis(lo: data[10], hi: data[11])
        let ly = stickToAxis(lo: data[12], hi: data[13], invert: true)
        let rx = stickToAxis(lo: data[14], hi: data[15])
        let ry = stickToAxis(lo: data[16], hi: data[17], invert: true)

        state.axes    = [lx, ly, lt, rt, rx, ry]
        state.buttons = buttons
        state.povs    = [pov]
        return true
    }
}

// MARK: - Shared helpers

private func stickToAxis(lo: UInt8, hi: UInt8, invert: Bool = false) -> Int8 {
    let raw = Int16(bitPattern: UInt16(lo) | UInt16(hi) << 8)
    let v = Int(raw) * 128 / 32768
    return Int8(clamping: invert ? -v : v)
}

private func dpadToPOV(up: Bool, down: Bool, left: Bool, right: Bool) -> Int16 {
    switch (up, down, left, right) {
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

// MARK: - USB Device Manager

/// Opens unclaimed Xbox-compatible USB controllers directly via IOKit USB
/// and reads their input reports, feeding into JoystickState.
@Observable
final class XboxUSBManager {
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var devices: [io_service_t: XboxUSBDevice] = [:]

    var onDeviceAdded:   ((UUID, JoystickState) -> Void)?
    var onDeviceRemoved: ((UUID) -> Void)?
    var onStateChanged:  ((UUID, JoystickState) -> Void)?
    var onLog: ((String) -> Void)?

    private func log(_ text: String) { onLog?(text) }

    func setRumble(deviceID: UUID, left: Double, right: Double) {
        for (_, dev) in devices {
            if dev.id == deviceID {
                dev.setRumble(left: left, right: right)
                return
            }
        }
    }

    /// Known Xbox-compatible vendor/product pairs that macOS doesn't natively support.
    private static let knownDevices: [(vendorID: Int, productID: Int)] = [
        (0x0e6f, 0x02f5),  // PDP Wired Controller for Xbox Series X
        (0x0e6f, 0x02d5),  // PDP Wired Controller for Xbox One
        (0x0e6f, 0x0346),  // PDP Xbox One Afterglow
        (0x0e6f, 0x0246),  // PDP Xbox One Afterglow v2
        (0x24c6, 0x5b02),  // PowerA Xbox One
        (0x24c6, 0x543a),  // PowerA Spectra
        (0x0f0d, 0x00c1),  // Hori Pad Mini
        (0x0f0d, 0x0067),  // Hori Pad Xbox One
        (0x1532, 0x0a03),  // Razer Wildcat
        (0x1532, 0x0a29),  // Razer Wolverine V2
    ]

    func start() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort else {
            log("XboxUSB: failed to create notification port")
            return
        }
        IONotificationPortSetDispatchQueue(notifyPort, .main)

        // Register a separate notification for each known vendor/product pair
        for device in Self.knownDevices {
            var matching = IOServiceMatching("IOUSBHostDevice") as! [String: Any]
            matching["idVendor"] = device.vendorID
            matching["idProduct"] = device.productID

            var iterator: io_iterator_t = 0
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let kr = IOServiceAddMatchingNotification(
                notifyPort,
                kIOFirstMatchNotification,
                matching as CFDictionary,
                { ctx, iterator in
                    guard let ctx else { return }
                    let mgr = Unmanaged<XboxUSBManager>.fromOpaque(ctx).takeUnretainedValue()
                    DispatchQueue.main.async { MainActor.assumeIsolated { mgr.handleMatched(iterator) } }
                },
                selfPtr,
                &iterator
            )
            if kr == KERN_SUCCESS {
                // Drain existing matches
                handleMatched(iterator)
                iterators.append(iterator)
            }
        }

        log("XboxUSB: started, monitoring \(Self.knownDevices.count) known device(s)")
    }

    func stop() {
        for (_, dev) in devices { dev.close() }
        devices.removeAll()
        for it in iterators { IOObjectRelease(it) }
        iterators.removeAll()
        if let np = notifyPort { IONotificationPortDestroy(np); notifyPort = nil }
    }

    private func handleMatched(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            let vid = getDeviceProperty(service, key: "idVendor") ?? 0
            let pid = getDeviceProperty(service, key: "idProduct") ?? 0
            let name = getDeviceStringProperty(service, key: "USB Product Name") ?? "Xbox Controller"
            log("XboxUSB: matched \"\(name)\" (0x\(String(vid, radix: 16)):0x\(String(pid, radix: 16)))")

            let dev = XboxUSBDevice(service: service, name: name, log: { [weak self] in self?.log($0) })
            dev.onStateChanged = { [weak self] id, state in
                self?.onStateChanged?(id, state)
            }
            dev.onDisconnected = { [weak self] id in
                self?.devices.removeValue(forKey: service)
                self?.onDeviceRemoved?(id)
            }

            if dev.open() {
                devices[service] = dev
                onDeviceAdded?(dev.id, dev.state)
            } else {
                log("XboxUSB: failed to open \"\(name)\"")
                IOObjectRelease(service)
            }
        }
    }

    private func getDeviceProperty(_ service: io_service_t, key: String) -> Int? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }

    private func getDeviceStringProperty(_ service: io_service_t, key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}

// MARK: - Single USB Device

private final class XboxUSBDevice {
    let id = UUID()
    let name: String
    var state: JoystickState

    var onStateChanged:  ((UUID, JoystickState) -> Void)?
    var onDisconnected:  ((UUID) -> Void)?

    private let service: io_service_t
    private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>>?
    private var interfaceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>>?
    private var readBuffer = [UInt8](repeating: 0, count: 64)
    private var lastReadLength: Int = 0
    private var readSource: CFRunLoopSource?
    private var pipeRefIn: UInt8 = 0
    private var pipeRefOut: UInt8 = 0
    private let log: (String) -> Void
    private var reportCount = 0

    init(service: io_service_t, name: String, log: @escaping (String) -> Void) {
        self.service = service
        self.name = name
        self.log = log
        self.state = JoystickState(
            axes: [0, 0, 0, 0, 0, 0],
            buttons: [Bool](repeating: false, count: 10),
            povs: [-1],
            name: name,
            isXbox: true,
            type: 1  // GamePad
        )
    }

    func open() -> Bool {
        // Get device interface
        var score: Int32 = 0
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?

        var kr = IOCreatePlugInInterfaceForService(
            service, kUSBDeviceUserClientTypeID, kCFPlugInInterfaceID,
            &plugInInterface, &score)
        guard kr == KERN_SUCCESS, let plugInInterface, let plugin = plugInInterface.pointee else {
            log("XboxUSB: IOCreatePlugInInterface for device failed: 0x\(String(kr, radix: 16))")
            return false
        }

        var devPtr: UnsafeMutableRawPointer?
        let usbDevID = CFUUIDGetUUIDBytes(kUSBDeviceInterfaceID)
        let hr = plugin.pointee.QueryInterface(
            UnsafeMutableRawPointer(plugInInterface), usbDevID, &devPtr)
        _ = plugin.pointee.Release(UnsafeMutableRawPointer(plugInInterface))
        guard hr == S_OK, let rawDev = devPtr else {
            log("XboxUSB: QueryInterface for device failed")
            return false
        }
        deviceInterface = rawDev.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBDeviceInterface>.self)

        guard let dev = deviceInterface else { return false }

        // Open device
        kr = dev.pointee.pointee.USBDeviceOpen(dev)
        guard kr == KERN_SUCCESS else {
            log("XboxUSB: USBDeviceOpen failed: 0x\(String(kr, radix: 16))")
            return false
        }

        // Set configuration (configuration 1)
        kr = dev.pointee.pointee.SetConfiguration(dev, 1)
        guard kr == KERN_SUCCESS else {
            log("XboxUSB: SetConfiguration failed: 0x\(String(kr, radix: 16))")
            dev.pointee.pointee.USBDeviceClose(dev)
            return false
        }

        // Find and open interface 0
        guard openInterface(dev) else {
            dev.pointee.pointee.USBDeviceClose(dev)
            return false
        }

        // Start reading
        startReading()
        return true
    }

    private func openInterface(_ dev: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>>) -> Bool {
        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kUSBVendorSpecificClass),  // 0xFF
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )

        var iterator: io_iterator_t = 0
        var kr = dev.pointee.pointee.CreateInterfaceIterator(dev, &request, &iterator)
        guard kr == KERN_SUCCESS else {
            log("XboxUSB: CreateInterfaceIterator failed: 0x\(String(kr, radix: 16))")
            return false
        }
        defer { IOObjectRelease(iterator) }

        // Get first interface
        let ifService = IOIteratorNext(iterator)
        guard ifService != 0 else {
            log("XboxUSB: no interfaces found")
            return false
        }
        defer { IOObjectRelease(ifService) }

        var score: Int32 = 0
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        kr = IOCreatePlugInInterfaceForService(
            ifService, kUSBInterfaceUserClientID, kCFPlugInInterfaceID,
            &plugInInterface, &score)
        guard kr == KERN_SUCCESS, let plugInInterface, let plugin = plugInInterface.pointee else {
            log("XboxUSB: IOCreatePlugInInterface for interface failed")
            return false
        }

        var ifPtr: UnsafeMutableRawPointer?
        let ifID = CFUUIDGetUUIDBytes(kUSBInterfaceInterfaceID)
        let hr = plugin.pointee.QueryInterface(
            UnsafeMutableRawPointer(plugInInterface), ifID, &ifPtr)
        _ = plugin.pointee.Release(UnsafeMutableRawPointer(plugInInterface))
        guard hr == S_OK, let rawIf = ifPtr else {
            log("XboxUSB: QueryInterface for interface failed")
            return false
        }
        interfaceInterface = rawIf.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBInterfaceInterface>.self)

        guard let iface = interfaceInterface else { return false }

        kr = iface.pointee.pointee.USBInterfaceOpen(iface)
        guard kr == KERN_SUCCESS else {
            log("XboxUSB: USBInterfaceOpen failed: 0x\(String(kr, radix: 16))")
            return false
        }

        // Find interrupt IN and OUT pipes
        var numEndpoints: UInt8 = 0
        iface.pointee.pointee.GetNumEndpoints(iface, &numEndpoints)

        for pipe: UInt8 in 1...max(numEndpoints, 1) {
            var direction: UInt8 = 0
            var number: UInt8 = 0
            var transferType: UInt8 = 0
            var maxPacketSize: UInt16 = 0
            var interval: UInt8 = 0
            iface.pointee.pointee.GetPipeProperties(
                iface, pipe, &direction, &number, &transferType, &maxPacketSize, &interval)

            if transferType == 3 {  // Interrupt
                if direction == 1 && pipeRefIn == 0 {
                    pipeRefIn = pipe
                    log("XboxUSB: found interrupt IN pipe \(pipe), maxPacket=\(maxPacketSize)")
                } else if direction == 0 && pipeRefOut == 0 {
                    pipeRefOut = pipe
                    log("XboxUSB: found interrupt OUT pipe \(pipe)")
                }
            }
        }

        guard pipeRefIn != 0 else {
            log("XboxUSB: no interrupt IN endpoint found")
            iface.pointee.pointee.USBInterfaceClose(iface)
            return false
        }

        // Add event source for async I/O
        var source: Unmanaged<CFRunLoopSource>?
        iface.pointee.pointee.CreateInterfaceAsyncEventSource(iface, &source)
        if let src = source?.takeRetainedValue() {
            readSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }

        return true
    }

    private func startReading() {
        // Send GIP power-on init packet so the controller starts sending input reports
        if pipeRefOut != 0, let iface = interfaceInterface {
            var initPacket: [UInt8] = [0x05, 0x20, 0x00, 0x01, 0x00]
            let kr = iface.pointee.pointee.WritePipe(
                iface, pipeRefOut, &initPacket, UInt32(initPacket.count))
            if kr == KERN_SUCCESS || kr == kIOReturnSuccess {
                log("XboxUSB: sent GIP init packet")
            } else {
                log("XboxUSB: GIP init write failed: 0x\(String(kr, radix: 16))")
            }
        }
        scheduleRead()
    }

    private func scheduleRead() {
        guard let iface = interfaceInterface, pipeRefIn != 0 else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let kr = iface.pointee.pointee.ReadPipeAsync(
            iface, pipeRefIn, &readBuffer, UInt32(readBuffer.count),
            { ctx, result, actualLen in
                guard let ctx else { return }
                let dev = Unmanaged<XboxUSBDevice>.fromOpaque(ctx).takeUnretainedValue()
                let len = Int(bitPattern: actualLen)
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    if result == KERN_SUCCESS || result == kIOReturnSuccess {
                        dev.lastReadLength = len
                        dev.handleReport()
                    } else {
                        dev.log("XboxUSB: read error 0x\(String(result, radix: 16)), disconnecting")
                        dev.onDisconnected?(dev.id)
                    }
                }}
            },
            selfPtr
        )
        if kr != KERN_SUCCESS && kr != kIOReturnSuccess {
            log("XboxUSB: ReadPipeAsync failed: 0x\(String(kr, radix: 16))")
        }
    }

    private func handleReport() {
        let len = lastReadLength
        guard len > 0 else { scheduleRead(); return }

        readBuffer.withUnsafeBufferPointer { fullBuf in
            let buf = UnsafeBufferPointer(rebasing: fullBuf.prefix(len))

            let cmd = buf[0]
            if reportCount < 5 {
                let hex = buf.prefix(min(len, 24)).map { String(format: "%02x", $0) }.joined(separator: " ")
                log("XboxUSB: report #\(reportCount) cmd=0x\(String(format: "%02x", cmd)) (\(len)B): \(hex)")
            }
            reportCount += 1

            // Only process input reports; skip GIP announce (0x02), ack (0x01), etc.
            if GIPReport.parse(buf, into: &state) || XInputReport.parse(buf, into: &state) {
                onStateChanged?(id, state)
            }
        }

        // Zero the buffer before next read to avoid stale data
        readBuffer.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        scheduleRead()
    }

    func setRumble(left: Double, right: Double) {
        guard let iface = interfaceInterface, pipeRefOut != 0 else { return }
        let l = UInt8(clamping: Int(left * 255))
        let r = UInt8(clamping: Int(right * 255))
        // GIP rumble command: cmd=0x09, client=0x00, seq=0x00, size=0x09
        // motors mask 0x0F = all four motors, trigger L, trigger R, main L, main R
        var packet: [UInt8] = [
            0x09, 0x00, 0x00, 0x09,  // header
            0x00, 0x0F,              // sub-command, motors mask
            0x00, 0x00,              // trigger L, trigger R (unused)
            l, r,                    // main left, main right
            0xFF, 0x00, 0x00         // duration, delay, repeat
        ]
        iface.pointee.pointee.WritePipe(iface, pipeRefOut, &packet, UInt32(packet.count))
    }

    func close() {
        if let src = readSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            readSource = nil
        }
        if let iface = interfaceInterface {
            iface.pointee.pointee.USBInterfaceClose(iface)
            interfaceInterface = nil
        }
        if let dev = deviceInterface {
            dev.pointee.pointee.USBDeviceClose(dev)
            deviceInterface = nil
        }
    }
}
