import SwiftUI

struct JoystickView: View {
    @Environment(AppState.self)   private var appState
    @Environment(HIDManager.self) private var hidManager
    @State private var selectedSlot: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(appState.joystickSlots.indices, id: \.self) { i in
                    SlotListRow(
                        index:       i,
                        slot:        appState.joystickSlots[i],
                        selected:    selectedSlot == i,
                        canMoveUp:   i > 0,
                        canMoveDown: i < appState.joystickSlots.count - 1,
                        onSelect:    { selectedSlot = i },
                        onMoveUp:    { appState.joystickSlots.swapAt(i, i - 1); selectedSlot = i - 1 },
                        onMoveDown:  { appState.joystickSlots.swapAt(i, i + 1); selectedSlot = i + 1 }
                    )
                    if i < appState.joystickSlots.count - 1 { Divider() }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 240)
            .background(.background.secondary)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.upArrow)   { moveSelected(by: -1); return .handled }
            .onKeyPress(.downArrow) { moveSelected(by:  1); return .handled }

            Divider()

            inputPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func moveSelected(by delta: Int) {
        let next = selectedSlot + delta
        guard next >= 0, next < appState.joystickSlots.count else { return }
        appState.joystickSlots.swapAt(selectedSlot, next)
        selectedSlot = next
    }

    @ViewBuilder
    private var inputPanel: some View {
        let idx = selectedSlot
        let slot = appState.joystickSlots[idx]
        if let state = slot.state {
            ScrollView(.vertical, showsIndicators: false) {
                InputDisplay(state: state)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "gamecontroller")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
                Text("Slot \(idx + 1) — No joystick assigned")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                if !hidManager.connectedDevices.isEmpty {
                    SlotPicker(slotIndex: idx)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Slot list row

private struct SlotListRow: View {
    let index:       Int
    let slot:        JoystickSlot
    let selected:    Bool
    let canMoveUp:   Bool
    let canMoveDown: Bool
    let onSelect:    () -> Void
    let onMoveUp:    () -> Void
    let onMoveDown:  () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Slot number
            Text("\(index + 1)")
                .font(.body.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            // Name + activity
            VStack(alignment: .leading, spacing: 3) {
                if let state = slot.state {
                    Text(state.name.isEmpty ? "Joystick \(index + 1)" : state.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 2) {
                        ForEach(state.buttons.prefix(16).indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(state.buttons[i] ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: 7, height: 7)
                        }
                    }
                } else {
                    Text("Empty")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Up/down arrows
            VStack(spacing: 2) {
                Button { onMoveUp() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!canMoveUp)

                Button { onMoveDown() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDown)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(selected ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - Slot picker (shown when slot is empty but devices exist)

private struct SlotPicker: View {
    @Environment(AppState.self)   private var appState
    @Environment(HIDManager.self) private var hidManager
    let slotIndex: Int

    var body: some View {
        Picker("Assign device", selection: Binding(
            get: { appState.joystickSlots[slotIndex].deviceID },
            set: { newID in
                // Clear the device from any other slot first
                if let id = newID {
                    for i in appState.joystickSlots.indices where appState.joystickSlots[i].deviceID == id && i != slotIndex {
                        appState.joystickSlots[i] = .empty
                    }
                }
                if let id = newID, let state = hidManager.currentState(for: id) {
                    appState.joystickSlots[slotIndex] = JoystickSlot(deviceID: id, state: state)
                } else {
                    appState.joystickSlots[slotIndex] = .empty
                }
            }
        )) {
            Text("— None —").tag(Optional<UUID>.none)
            ForEach(hidManager.connectedDevices) { dev in
                Text(dev.name).tag(Optional(dev.id))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 240)
    }
}

// MARK: - Input display

private struct InputDisplay: View {
    let state: JoystickState

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Axes column
            if !state.axes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AXES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(1)

                    ForEach(state.axes.indices, id: \.self) { i in
                        AxisRow(index: i, value: state.axes[i])
                    }
                }
                .frame(width: 240)
            }

            if !state.axes.isEmpty && (!state.buttons.isEmpty || !state.povs.isEmpty) {
                Divider()
            }

            // Buttons + POVs
            VStack(alignment: .leading, spacing: 14) {
                if !state.buttons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BUTTONS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .kerning(1)

                        ButtonGrid(buttons: state.buttons)
                    }
                }

                if !state.povs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("POVS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .kerning(1)

                        HStack(spacing: 10) {
                            ForEach(state.povs.indices, id: \.self) { i in
                                let angle = state.povs[i]
                                Text(angle < 0 ? "—" : "\(angle)°")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(angle < 0 ? .tertiary : .primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(angle < 0 ? .clear : Color.accentColor.opacity(0.15))
                                    )
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AxisRow: View {
    let index: Int
    let value: Int8

    private var fraction: Double { (Double(value) + 128.0) / 255.0 }

    var body: some View {
        HStack(spacing: 8) {
            Text("A\(index + 1)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            GeometryReader { geo in
                let w = geo.size.width
                let center = w / 2
                let end = fraction * w
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                        .offset(x: center - 0.5)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: abs(end - center))
                        .offset(x: min(center, end))
                }
            }
            .frame(height: 18)

            Text(String(format: "%+.0f", Double(value) / 127.0 * 100))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private struct ButtonGrid: View {
    let buttons: [Bool]

    let columns = Array(repeating: GridItem(.fixed(36), spacing: 5), count: 10)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(buttons.indices, id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(buttons[i] ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 36, height: 28)
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(buttons[i] ? .white : .secondary)
                }
            }
        }
    }
}
