import SwiftUI
import AppKit

// MARK: - Navigation

enum NavTab: String, CaseIterable, Hashable {
    case control     = "Control"
    case joysticks   = "USB Devices"
    case diagnostics = "Diagnostics"
    case log         = "Log"
}

// MARK: - Root view

struct ContentView: View {
    @Environment(AppState.self)             private var state
    @Environment(DSConnection.self)         private var connection
    @Environment(HIDManager.self)           private var hidManager
    @Environment(PCDiagnosticsMonitor.self) private var pcDiag
    @Environment(KeybindManager.self)       private var keybinds

    @State private var tab: NavTab = .control

    var body: some View {
        Group {
            switch tab {
            case .control:     ControlTab()
            case .joysticks:   JoystickView()
            case .diagnostics: TelemetryView()
            case .log:         LogView().frame(minHeight: 400)
            }
        }
        .frame(minWidth: 820, minHeight: tab == .log ? 400 : 220)
        // Dynamic keybind shortcuts
        .overlay {
            Group {
                bindButton(.tabControl)     { tab = .control }
                bindButton(.tabJoysticks)   { tab = .joysticks }
                bindButton(.tabDiagnostics) { tab = .diagnostics }
                bindButton(.tabLog)         { tab = .log }
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    ForEach(NavTab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if state.connectionState == .disconnected { connection.connect() }
                    else { connection.disconnect() }
                } label: {
                    Label(
                        state.connectionState == .disconnected ? "Connect" : "Disconnect",
                        systemImage: state.connectionState == .disconnected
                            ? "network" : "network.slash"
                    )
                }
                .labelStyle(.iconOnly)
                .modifier(DynamicShortcut(keybinds.binding(for: .connectToggle)))

                BatteryView(voltage: state.batteryVoltage, history: state.batteryHistory)
            }
        }
        .onChange(of: tab) { _, newTab in
            if newTab != .log, let win = NSApp.keyWindow {
                win.setContentSize(CGSize(width: win.frame.width, height: 320))
            }
        }
        .background(WindowConfigurator())
    }
}

// MARK: - Control tab

private struct ControlTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ModePanel()
                .frame(width: 190)
                .padding()

            Divider()

            PCStatsPanel()
                .frame(width: 220)
                .padding()

            Divider()

            RobotStatusPanel()
                .padding()
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Mode + Enable/Disable

private struct ModePanel: View {
    @Environment(AppState.self)       private var state
    @Environment(DSConnection.self)   private var connection
    @Environment(KeybindManager.self) private var keybinds

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Team #") {
                TextField("", value: $state.teamNumber, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
            }

            Divider()

            Picker("Mode", selection: $state.mode) {
                ForEach(RobotMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .onChange(of: state.mode) { state.isEnabled = false }
            // Mode shortcuts (hidden buttons)
            .overlay {
                Group {
                    bindButton(.modeTeleop, keybinds) { state.mode = .teleop; state.isEnabled = false }
                    bindButton(.modeAuto, keybinds)   { state.mode = .auto;   state.isEnabled = false }
                    bindButton(.modeTest, keybinds)    { state.mode = .test;   state.isEnabled = false }
                }
                .opacity(0).allowsHitTesting(false)
            }

            Divider()

            Button(state.isEnabled ? "Disable" : "Enable") {
                state.isEnabled.toggle()
            }
            .buttonStyle(WideButtonStyle(fill: state.isEnabled ? Color(red: 0.75, green: 0.1, blue: 0.1) : .green))
            .disabled(!canEnable)
            .opacity(canEnable ? 1 : 0.45)
            // Enable/disable shortcuts
            .overlay {
                Group {
                    bindButton(.disable, keybinds)       { state.isEnabled = false }
                    bindButton(.enableDisable, keybinds)  { state.isEnabled.toggle() }
                }
                .opacity(0).allowsHitTesting(false)
            }

            Divider()

            HStack(spacing: 6) {
                Button { state.pendingReboot = true } label: {
                    Label("Reboot RIO", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .modifier(DynamicShortcut(keybinds.binding(for: .rebootRIO)))

                Button { state.pendingRestartCode = true } label: {
                    Label("Restart Code", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .modifier(DynamicShortcut(keybinds.binding(for: .restartCode)))
            }
            .disabled(!state.robotCommsOK)
            .opacity(state.robotCommsOK ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
    }

    private var canEnable: Bool { state.robotCommsOK && !state.isEStopped }
}

// MARK: - PC stats + controls

private struct PCStatsPanel: View {
    @Environment(AppState.self)             private var state
    @Environment(PCDiagnosticsMonitor.self) private var pcDiag
    @Environment(KeybindManager.self)       private var keybinds

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 10) {
            // Status indicators — horizontal row
            HStack(spacing: 10) {
                DSStatusRow(label: "Comms",    ok: state.robotCommsOK)
                DSStatusRow(label: "Code",     ok: state.robotCodeOK)
                DSStatusRow(label: "Joystick", ok: state.joysticksOK)
            }

            Divider()

            LabeledContent("Elapsed Time") {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    Text(elapsedString)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
            }

            Divider()

            // PC Battery
            if pcDiag.batteryPct >= 0 {
                LabeledContent {
                    MiniBar(value: pcDiag.batteryPct / 100,
                            color: pcDiag.batteryPct > 20 ? .green : .red)
                } label: {
                    Label(
                        pcDiag.isCharging ? "Charging" : "PC Battery",
                        systemImage: pcDiag.isCharging ? "bolt.fill" : "battery.75percent"
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
            }

            // PC CPU
            LabeledContent {
                MiniBar(value: pcDiag.cpuUsage / 100,
                        color: pcDiag.cpuUsage > 80 ? .red : .accentColor)
            } label: {
                Label("PC CPU", systemImage: "cpu")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Divider()

            LabeledContent("Team Station") {
                Picker("", selection: $state.allianceStation) {
                    ForEach(AllianceStation.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            Divider()

            // E-STOP
            Button {
                state.isEStopped = true
                state.isEnabled  = false
            } label: {
                Text("E-STOP")
                    .fontWeight(.black)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.isEStopped ? .red.opacity(0.6) : .red)
            .controlSize(.large)
            .modifier(DynamicShortcut(keybinds.binding(for: .eStop)))
            .disabled(!state.robotCommsOK)
            .opacity(state.robotCommsOK ? 1 : 0.45)
        }
    }

    private var elapsedString: String {
        guard let start = state.enabledAt, state.isEnabled else { return "0:00.0" }
        let t = Date().timeIntervalSince(start)
        return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
}

private struct MiniBar: View {
    let value: Double   // 0…1
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: g.size.width * min(1, max(0, value)))
            }
        }
        .frame(width: 80, height: 8)
    }
}

// MARK: - Robot status

private struct RobotStatusPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MiniLogView()
        }
    }
}

private struct DSStatusRow: View {
    let label: String
    let ok:    Bool

    var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(ok ? Color.green : Color(red: 0.85, green: 0.1, blue: 0.1))
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mini log

private struct MiniLogView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("LOG")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(1)

            ForEach(state.logMessages.suffix(4).reversed()) { msg in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: levelIcon(msg.level))
                        .foregroundStyle(levelColor(msg.level))
                        .font(.system(size: 9))
                        .frame(width: 10)
                    Text(msg.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(msg.level == .error ? Color.red : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelIcon(_ l: LogMessage.Level) -> String {
        switch l {
        case .print:   return "text.alignleft"
        case .info:    return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error:   return "xmark.circle"
        }
    }

    private func levelColor(_ l: LogMessage.Level) -> Color {
        switch l {
        case .print:   return .secondary
        case .info:    return .accentColor
        case .warning: return .yellow
        case .error:   return .red
        }
    }
}

// MARK: - Wide button style

private struct WideButtonStyle: ButtonStyle {
    let fill: Color?   // nil = outlined/secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(fill != nil ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(fill.map { configuration.isPressed ? $0.opacity(0.75) : $0 } ?? Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(fill != nil ? .clear : Color.secondary.opacity(0.5), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed && fill == nil ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Dynamic keybind helpers

/// ViewModifier that applies a dynamic keyboard shortcut from a KeyCombo
struct DynamicShortcut: ViewModifier {
    let combo: KeyCombo?

    init(_ combo: KeyCombo?) { self.combo = combo }

    func body(content: Content) -> some View {
        if let combo {
            content.keyboardShortcut(combo.keyEquivalent, modifiers: combo.eventModifiers)
        } else {
            content
        }
    }
}

/// Creates a hidden button wired to a keybind action (used from ContentView which has keybinds in environment)
@ViewBuilder
private func bindButton(_ action: KeybindAction, _ keybinds: KeybindManager, perform: @escaping () -> Void) -> some View {
    if let combo = keybinds.binding(for: action) {
        Button("", action: perform)
            .keyboardShortcut(combo.keyEquivalent, modifiers: combo.eventModifiers)
    }
}

extension ContentView {
    @ViewBuilder
    func bindButton(_ action: KeybindAction, perform: @escaping () -> Void) -> some View {
        if let combo = keybinds.binding(for: action) {
            Button("", action: perform)
                .keyboardShortcut(combo.keyEquivalent, modifiers: combo.eventModifiers)
        }
    }
}

// MARK: - Floating window

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let win = view.window else { return }
            win.level                       = .floating
            win.isMovableByWindowBackground = false
            win.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.setContentSize(CGSize(width: win.frame.width, height: 320))
            win.makeFirstResponder(nil)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
