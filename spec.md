# DriverKit — FRC Driver Station for macOS

A native macOS FRC Driver Station replacement, built with Swift/SwiftUI for Apple Silicon.
Not competition-legal (per FRC Game Manual R710/R901) — for testing and practice only.

---

## Goals

- Native macOS app, Apple Silicon first
- Full feature parity with the NI Driver Station for testing purposes
- Clean SwiftUI interface that feels at home on macOS
- No Wine, no Windows VM

---

## Non-Goals

- FMS integration (competition use is prohibited anyway)
- roboRIO imaging
- LabVIEW deployment
- Windows/Linux support (use Conductor or OpenDS for those)

---

## Protocol

The FRC DS protocol is documented at https://frcnetworking.readthedocs.io

### Robot IP
```
10.TE.AM.2
```
Where `TE` and `AM` are the first two and last two digits of the team number.
Example: Team 1234 → `10.12.34.2`

---

### DS → Robot (UDP, port 1110) — 50 Hz

Sent every 20ms.

#### Packet structure

| Field | Size | Description |
|---|---|---|
| Sequence number | 2 bytes (uint16, big-endian) | Incremented each packet |
| Comm version | 1 byte | Always `0x01` |
| Control byte | 1 byte | Mode and state flags |
| Request byte | 1 byte | Reboot/restart flags |
| Alliance byte | 1 byte | Station assignment |
| Tags | Variable | Joysticks, date, timezone |

#### Control byte

| Bit | Meaning |
|---|---|
| 7 | E-Stop |
| 3 | FMS Connected |
| 2 | Enabled |
| 1–0 | Mode: `00`=Teleop, `01`=Test, `10`=Auto |

#### Request byte

| Bit | Meaning |
|---|---|
| 3 | Reboot roboRIO |
| 2 | Restart robot code |

#### Alliance byte
- Values 0–2: Red 1/2/3
- Values 3–5: Blue 1/2/3

#### Tags (format: `[size: u8][id: u8][data...]`)

| ID | Name | Data |
|---|---|---|
| `0x07` | Countdown | 4-byte float, seconds remaining |
| `0x0c` | Joystick | See below |
| `0x0f` | Date/Time | microseconds(u32), second, minute, hour, day, month, year-since-1900 — sent once on connect |
| `0x10` | Timezone | Variable-length string — sent once on connect |

#### Joystick tag (`0x0c`) structure
```
axis_count: u8
axes: [i8; axis_count]         // −128..127
button_count: u8
buttons: packed bits, ceil(button_count/8) bytes
pov_count: u8
povs: [i16; pov_count]         // 0–360°, −1 = unpressed
```

---

### Robot → DS (UDP, port 1150) — 50 Hz

#### Packet structure

| Field | Size | Description |
|---|---|---|
| Sequence number | 2 bytes | |
| Comm version | 1 byte | `0x01` |
| Status byte | 1 byte | E-Stop, brownout, code init, enabled, mode |
| Trace byte | 1 byte | Code running, mode state |
| Battery | 2 bytes | `integer + (fraction/256)` volts |
| Request date | 1 byte | Non-zero = robot requesting date/time |
| Tags | Variable | CPU/RAM/disk usage, CAN metrics, PDP currents |

---

### DS → Robot (TCP, port 1740) — event-driven

Sent on connection or when joystick configuration changes.

| Tag ID | Name | Trigger |
|---|---|---|
| `0x02` | Joystick descriptor | On plug/unplug/reorder |
| `0x07` | Match info | On connect |
| `0x0e` | Game data string | On user input |

#### Joystick descriptor (`0x02`)
```
joystick_index: u8
is_xbox: u8
type: u8
name: [u8; 16]        // null-padded
axis_count: u8
axis_types: [u8; axis_count]
button_count: u8
pov_count: u8
```

---

### Robot → DS (TCP, port 1740) — event-driven

- Device version strings (roboRIO image version, WPILib version, CAN device versions)
- Error/warning messages with timestamps and stack traces
- stdout log lines from robot code

---

## Features

### Core
- [ ] Enable / Disable robot
- [ ] E-Stop
- [ ] Mode selection: Teleoperated, Autonomous, Test
- [ ] Team number configuration → auto-derive robot IP
- [ ] Battery voltage display
- [ ] Connection status indicators (DS comms, robot code, joysticks)
- [ ] Reboot roboRIO
- [ ] Restart robot code

### Joysticks
- [ ] Enumerate USB HID devices via IOKit
- [ ] Map devices to slots 0–5
- [ ] Axis, button, and POV reading
- [ ] Drag-and-drop slot reordering
- [ ] Joystick descriptor transmission via TCP
- [ ] Persist slot assignments across reconnects

### Telemetry
- [ ] Battery voltage with trend chart
- [ ] roboRIO CPU, RAM, disk usage
- [ ] CAN bus utilization and fault counts
- [ ] Trip time and packet loss
- [ ] Brownout indicator

### Logging
- [ ] Robot stdout log viewer
- [ ] Error/warning display with timestamps
- [ ] Log export

### Practice Mode
- [ ] Configurable autonomous, teleop, endgame countdown timers
- [ ] Auto-enable/disable sequencing

### Game Data
- [ ] Game data string input (for testing autonomous game-piece logic)

---

## Architecture

### Tech Stack
- **Language**: Swift
- **UI**: SwiftUI
- **Networking**: `Network.framework` (NWConnection for UDP + TCP)
- **Joystick input**: IOKit HID (`IOHIDManager`)
- **Persistence**: `UserDefaults` or a small JSON config file

### Key Components

```
DriverKit/
├── Network/
│   ├── DSConnection.swift       # Main connection state machine
│   ├── UDPSender.swift          # 50Hz packet dispatch to robot
│   ├── UDPReceiver.swift        # Receive robot status packets
│   ├── TCPChannel.swift         # TCP tag send/receive
│   └── PacketBuilder.swift      # Build outbound DS packets
├── Protocol/
│   ├── ControlPacket.swift      # Control/request/alliance byte logic
│   ├── StatusPacket.swift       # Parse robot → DS UDP packets
│   ├── Tags.swift               # Encode/decode all tag types
│   └── JoystickDescriptor.swift # TCP joystick descriptor encoding
├── Input/
│   ├── HIDManager.swift         # IOKit HID enumeration + events
│   ├── JoystickSlots.swift      # Slot assignment and persistence
│   └── JoystickState.swift      # Current axis/button/POV values
├── Views/
│   ├── ContentView.swift        # Main window layout
│   ├── ControlPanel.swift       # Enable/disable/mode/estop
│   ├── StatusIndicators.swift   # Comms/code/joystick lights
│   ├── BatteryView.swift        # Voltage + trend
│   ├── JoystickView.swift       # Slot management UI
│   ├── TelemetryView.swift      # CPU/RAM/CAN stats
│   └── LogView.swift            # Robot stdout/error log
└── App/
    ├── DriverKitApp.swift
    └── AppState.swift           # Observable app-wide state
```

### Connection State Machine
```
Disconnected → Connecting → Connected → Enabled
                                ↑            ↓
                             Disabled ←──────┘
                                ↓
                             E-Stopped
```

---

## UDP Timing

- Send at exactly 50 Hz (every 20ms) using a `DispatchSourceTimer` or Swift concurrency `AsyncStream`
- Sequence number wraps at `UInt16.max`
- If no response received for 500ms → mark communications lost

---

## Joystick HID (IOKit)

```swift
// Rough outline
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria)
IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceAdded, context)
IOHIDManagerRegisterInputValueCallback(manager, inputReceived, context)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
```

Axis values from HID are typically in a device-defined range — normalize to `−128..127` (int8) as required by the DS protocol.

---

## Resources

### Protocol Documentation
- **FRC Networking Docs** (primary reference): https://frcnetworking.readthedocs.io/en/latest/driverstation/
- **WPILib DS source** (robot-side API, not DS itself): https://github.com/wpilibsuite/allwpilib

### Reference Implementations
- **ds-rs** (Rust protocol library): https://github.com/first-rust-competition/ds-rs
- **Conductor** (Rust + React, macOS): https://github.com/Redrield/Conductor
- **OpenDS** (Java, macOS M1): https://github.com/Boomaa23/open-ds
- **QDriverStation** (C++/Qt): https://github.com/FRC-Utilities/QDriverStation
- **LibDS** (C protocol library): https://github.com/FRC-Utilities/LibDS

### Apple Frameworks
- **Network.framework** (UDP/TCP): https://developer.apple.com/documentation/network
- **IOKit HID** (joystick input): https://developer.apple.com/documentation/iokit

### FRC Documentation
- **DS User Guide**: https://docs.wpilib.org/en/stable/docs/software/driverstation/driver-station.html
- **roboRIO Networking**: https://docs.wpilib.org/en/stable/docs/networking/networking-introduction/index.html

---

## Limitations / Known Issues

- No FMS support (and not allowed at competition anyway)
- No roboRIO imaging tool
- USB passthrough for roboRIO direct USB connection may need additional entitlements
- mDNS resolution (`roborio-TEAM-frc.local`) requires `NSBonjourServices` entitlement

---

## Legal

Per FRC Game Manual rules **R710** and **R901**, only the official NI Driver Station may be used during FRC-legal competitions. DriverKit is for practice and testing only.
