import SwiftUI
import AppKit

struct KeybindSettingsView: View {
    @Environment(KeybindManager.self) private var keybinds
    @State private var recordingAction: KeybindAction? = nil

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(KeybindAction.sections, id: \.0) { section, actions in
                    Section(section) {
                        ForEach(actions) { action in
                            HStack {
                                Text(action.rawValue)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                ShortcutRecorderButton(
                                    combo: keybinds.binding(for: action),
                                    isRecording: recordingAction == action,
                                    onStartRecording: { recordingAction = action },
                                    onRecord: { combo in
                                        keybinds.set(combo, for: action)
                                        recordingAction = nil
                                    },
                                    onClear: {
                                        keybinds.set(nil, for: action)
                                        recordingAction = nil
                                    },
                                    onCancel: { recordingAction = nil }
                                )
                                .frame(width: 140)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    keybinds.resetToDefaults()
                    recordingAction = nil
                }
                .controlSize(.small)
                Spacer()
            }
            .padding(10)
        }
        .frame(width: 450, height: 420)
    }
}

// MARK: - Shortcut recorder button

private struct ShortcutRecorderButton: View {
    let combo: KeyCombo?
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onRecord: (KeyCombo) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            if isRecording {
                KeyRecorderView(onRecord: onRecord, onCancel: onCancel)
                    .frame(height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    )
            } else {
                HStack(spacing: 4) {
                    Text(combo?.displayString ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(combo != nil ? .primary : .tertiary)
                        .frame(maxWidth: .infinity)

                    if combo != nil {
                        Button {
                            onClear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.quaternary)
                )
                .onTapGesture { onStartRecording() }
            }
        }
    }
}

// MARK: - NSView key recorder

private struct KeyRecorderView: NSViewRepresentable {
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureField {
        let field = KeyCaptureField()
        field.onRecord = onRecord
        field.onCancel = onCancel
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: KeyCaptureField, context: Context) {}
}

final class KeyCaptureField: NSView {
    var onRecord: ((KeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    private let label = NSTextField(labelWithString: "Press shortcut…")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
            return
        }
        if let combo = KeyCombo.from(event: event) {
            onRecord?(combo)
        }
    }
}
