import SwiftUI

struct LogView: View {
    @Environment(AppState.self) private var state
    @State private var filterLevel: LogMessage.Level? = nil
    @State private var scrollProxy: ScrollViewProxy? = nil

    private var messages: [LogMessage] {
        guard let level = filterLevel else { return state.logMessages }
        return state.logMessages.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text("Log")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Filter", selection: $filterLevel) {
                    Text("All").tag(Optional<LogMessage.Level>.none)
                    Text("Print").tag(Optional(LogMessage.Level.print))
                    Text("Info").tag(Optional(LogMessage.Level.info))
                    Text("Warning").tag(Optional(LogMessage.Level.warning))
                    Text("Error").tag(Optional(LogMessage.Level.error))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)

                Button("Clear") { state.logMessages.removeAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 6)

            Divider()

            ScrollViewReader { proxy in
                List(messages) { msg in
                    LogRow(msg: msg)
                        .id(msg.id)
                        .listRowSeparator(.visible)
                }
                .listStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: state.logMessages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

private struct LogRow: View {
    let msg: LogMessage

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: msg.timestamp))
                .foregroundStyle(.tertiary)
                .frame(width: 90, alignment: .leading)

            Image(systemName: levelIcon)
                .foregroundStyle(levelColor)
                .frame(width: 12)

            Text(msg.text)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .lineLimit(nil)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private var levelIcon: String {
        switch msg.level {
        case .print:   "text.alignleft"
        case .info:    "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error:   "xmark.circle"
        }
    }

    private var levelColor: Color {
        switch msg.level {
        case .print:   .secondary
        case .info:    .accentColor
        case .warning: .yellow
        case .error:   .red
        }
    }

    private var textColor: Color {
        switch msg.level {
        case .error:   .red
        case .warning: .orange
        default:       .primary
        }
    }
}
