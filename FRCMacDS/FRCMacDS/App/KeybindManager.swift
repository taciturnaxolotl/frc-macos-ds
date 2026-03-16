import SwiftUI
import Carbon.HIToolbox

// MARK: - Actions

enum KeybindAction: String, CaseIterable, Identifiable {
    // Robot control
    case enableDisable   = "Enable / Disable"
    case disable         = "Disable"
    case eStop           = "E-STOP"

    // Modes
    case modeTeleop      = "Teleoperated"
    case modeAuto        = "Autonomous"
    case modeTest        = "Test"

    // Connection
    case connectToggle   = "Connect / Disconnect"

    // Robot actions
    case rebootRIO       = "Reboot RIO"
    case restartCode     = "Restart Code"

    // Tabs
    case tabControl      = "Tab: Control"
    case tabJoysticks    = "Tab: USB Devices"
    case tabDiagnostics  = "Tab: Diagnostics"
    case tabLog          = "Tab: Log"

    var id: String { rawValue }

    var section: String {
        switch self {
        case .enableDisable, .disable, .eStop:          "Robot Control"
        case .modeTeleop, .modeAuto, .modeTest:         "Mode Selection"
        case .connectToggle:                             "Connection"
        case .rebootRIO, .restartCode:                   "Robot Actions"
        case .tabControl, .tabJoysticks,
             .tabDiagnostics, .tabLog:                   "Navigation"
        }
    }

    static var sections: [(String, [KeybindAction])] {
        let order = ["Robot Control", "Mode Selection", "Connection", "Robot Actions", "Navigation"]
        return order.map { section in
            (section, allCases.filter { $0.section == section })
        }
    }
}

// MARK: - Key combo

struct KeyCombo: Codable, Equatable {
    var key: String              // character ("k") or special ("return", "space", etc.)
    var modifiers: UInt          // NSEvent.ModifierFlags rawValue (masked)

    static let modifierMask: UInt = NSEvent.ModifierFlags([.command, .shift, .option, .control]).rawValue

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { parts.append("^") }
        if flags.contains(.option)  { parts.append("\u{2325}") }
        if flags.contains(.shift)   { parts.append("\u{21E7}") }
        if flags.contains(.command) { parts.append("\u{2318}") }
        parts.append(keyDisplayName)
        return parts.joined()
    }

    var keyDisplayName: String {
        switch key {
        case "return":    "\u{21A9}"
        case "space":     "\u{2423}"
        case "escape":    "\u{238B}"
        case "delete":    "\u{232B}"
        case "tab":       "\u{21E5}"
        case "up":        "\u{2191}"
        case "down":      "\u{2193}"
        case "left":      "\u{2190}"
        case "right":     "\u{2192}"
        case " ":         "\u{2423}"
        default:          key.uppercased()
        }
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case "return": .return
        case "space":  .space
        case "escape": .escape
        case "delete": .delete
        case "tab":    .tab
        case "up":     .upArrow
        case "down":   .downArrow
        case "left":   .leftArrow
        case "right":  .rightArrow
        default:       KeyEquivalent(Character(key))
        }
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var m: SwiftUI.EventModifiers = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift)   { m.insert(.shift) }
        if flags.contains(.option)  { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        return m
    }

    static func from(event: NSEvent) -> KeyCombo? {
        let mods = event.modifierFlags.rawValue & modifierMask
        let key: String
        switch Int(event.keyCode) {
        case kVK_Return:       key = "return"
        case kVK_Space:        key = "space"
        case kVK_Escape:       key = "escape"
        case kVK_Delete:       key = "delete"
        case kVK_Tab:          key = "tab"
        case kVK_UpArrow:      key = "up"
        case kVK_DownArrow:    key = "down"
        case kVK_LeftArrow:    key = "left"
        case kVK_RightArrow:   key = "right"
        default:
            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  !chars.isEmpty else { return nil }
            key = chars
        }
        return KeyCombo(key: key, modifiers: mods)
    }
}

// MARK: - Manager

@Observable
final class KeybindManager {
    private(set) var bindings: [KeybindAction: KeyCombo]

    static let defaults: [KeybindAction: KeyCombo] = [
        .disable:        KeyCombo(key: "return", modifiers: 0),
        .eStop:          KeyCombo(key: "space",  modifiers: 0),
        .connectToggle:  KeyCombo(key: "k",      modifiers: NSEvent.ModifierFlags.command.rawValue),
        .modeTeleop:     KeyCombo(key: "t",      modifiers: NSEvent.ModifierFlags.command.rawValue),
        .modeAuto:       KeyCombo(key: "u",      modifiers: NSEvent.ModifierFlags.command.rawValue),
        .modeTest:       KeyCombo(key: "y",      modifiers: NSEvent.ModifierFlags.command.rawValue),
        .tabControl:     KeyCombo(key: "1",      modifiers: NSEvent.ModifierFlags.command.rawValue),
        .tabJoysticks:   KeyCombo(key: "2",      modifiers: NSEvent.ModifierFlags.command.rawValue),
        .tabDiagnostics: KeyCombo(key: "3",      modifiers: NSEvent.ModifierFlags.command.rawValue),
        .tabLog:         KeyCombo(key: "4",      modifiers: NSEvent.ModifierFlags.command.rawValue),
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: "keybindings"),
           let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            var result: [KeybindAction: KeyCombo] = [:]
            for (key, combo) in saved {
                if let action = KeybindAction(rawValue: key) {
                    result[action] = combo
                }
            }
            bindings = result
        } else {
            bindings = Self.defaults
        }
    }

    func binding(for action: KeybindAction) -> KeyCombo? {
        bindings[action]
    }

    func set(_ combo: KeyCombo?, for action: KeybindAction) {
        // Remove any existing binding with the same combo to avoid conflicts
        if let combo {
            for (existingAction, existingCombo) in bindings where existingCombo == combo && existingAction != action {
                bindings[existingAction] = nil
            }
        }
        bindings[action] = combo
        save()
    }

    func resetToDefaults() {
        bindings = Self.defaults
        save()
    }

    private func save() {
        var dict: [String: KeyCombo] = [:]
        for (action, combo) in bindings {
            dict[action.rawValue] = combo
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "keybindings")
        }
    }
}
