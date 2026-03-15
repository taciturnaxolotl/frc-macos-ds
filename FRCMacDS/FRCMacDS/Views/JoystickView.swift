import SwiftUI

struct JoystickView: View {
    @Environment(AppState.self)   private var appState
    @Environment(HIDManager.self) private var hidManager
    @State private var selectedSlot: Int? = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            List(selection: $selectedSlot) {
                ForEach(appState.joystickSlots.indices, id: \.self) { i in
                    SlotListRow(index: i, slot: appState.joystickSlots[i])
                        .tag(i)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .onMove { from, to in
                    appState.joystickSlots.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 240)

            Divider()

            inputPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var inputPanel: some View {
        let idx = selectedSlot ?? 0
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
    let index: Int
    let slot:  JoystickSlot

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                if let state = slot.state {
                    Text(state.name.isEmpty ? "Joystick \(index + 1)" : state.name)
                        .font(.callout)
                        .lineLimit(1)
                    HStack(spacing: 2) {
                        ForEach(state.buttons.prefix(16).indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(state.buttons[i] ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: 6, height: 6)
                        }
                    }
                } else {
                    Text("Empty")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if slot.state != nil {
                Circle().fill(.green).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 2)
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
        HStack(alignment: .top, spacing: 16) {
            // Axes column
            if !state.axes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AXES")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(1)

                    ForEach(state.axes.indices, id: \.self) { i in
                        AxisRow(index: i, value: state.axes[i])
                    }
                }
                .frame(width: 160)
            }

            if !state.axes.isEmpty && (!state.buttons.isEmpty || !state.povs.isEmpty) {
                Divider()
            }

            // Buttons + POVs
            VStack(alignment: .leading, spacing: 10) {
                if !state.buttons.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BUTTONS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .kerning(1)

                        ButtonGrid(buttons: state.buttons)
                    }
                }

                if !state.povs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("POVS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .kerning(1)

                        HStack(spacing: 8) {
                            ForEach(state.povs.indices, id: \.self) { i in
                                let angle = state.povs[i]
                                Text(angle < 0 ? "—" : "\(angle)°")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(angle < 0 ? .tertiary : .primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
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
        HStack(spacing: 6) {
            Text("A\(index + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            GeometryReader { geo in
                let w = geo.size.width
                let center = w / 2
                let end = fraction * w
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.12))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                        .offset(x: center - 0.5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: abs(end - center))
                        .offset(x: min(center, end))
                }
            }
            .frame(height: 10)

            Text(String(format: "%+.0f", Double(value) / 127.0 * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

private struct ButtonGrid: View {
    let buttons: [Bool]

    let columns = Array(repeating: GridItem(.fixed(22), spacing: 3), count: 16)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(buttons.indices, id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(buttons[i] ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 22, height: 18)
                    Text("\(i + 1)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(buttons[i] ? .white : .secondary)
                }
            }
        }
    }
}
