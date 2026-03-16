import SwiftUI
import AppKit

struct LogView: View {
    @Environment(AppState.self) private var state
    @State private var filterLevel: LogMessage.Level? = nil
    @State private var viewingSavedSession: LogSession? = nil

    private var isLive: Bool { viewingSavedSession == nil }

    private var displayMessages: [LogMessage] {
        let source: [LogMessage]
        if let saved = viewingSavedSession {
            source = saved.messages.map { $0.toLogMessage() }
        } else {
            source = state.logMessages
        }
        guard let level = filterLevel else { return source }
        return source.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Session picker
                Menu {
                    Button("Live") {
                        viewingSavedSession = nil
                    }

                    if !state.savedSessions.isEmpty {
                        Divider()
                        ForEach(state.savedSessions) { session in
                            Button("\(session.displayName) — Team \(session.teamNumber) (\(session.messages.count) msgs)") {
                                if let full = LogStore.shared.loadSession(id: session.id) {
                                    viewingSavedSession = full
                                }
                            }
                        }
                        Divider()
                        Button("Delete All Saved Logs") {
                            for session in state.savedSessions {
                                LogStore.shared.deleteSession(id: session.id)
                            }
                            state.refreshSavedSessions()
                            viewingSavedSession = nil
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isLive ? "circle.fill" : "clock")
                            .foregroundStyle(isLive ? .green : .secondary)
                            .font(.system(size: 8))
                        Text(isLive ? "Live" : (viewingSavedSession?.displayName ?? ""))
                            .font(.caption.bold())
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

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

                if isLive {
                    Button("Clear") { state.logMessages.removeAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("Back to Live") { viewingSavedSession = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 6)

            Divider()

            LogTextView(messages: displayMessages)
        }
        .onAppear { state.refreshSavedSessions() }
    }
}

// MARK: - NSTextView wrapper

private struct LogTextView: NSViewRepresentable {
    let messages: [LogMessage]

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable        = false
        textView.isSelectable      = true
        textView.drawsBackground   = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        let attr = buildAttributedString()
        textView.textStorage?.setAttributedString(attr)
        // Scroll to bottom
        textView.scrollToEndOfDocument(nil)
    }

    private func buildAttributedString() -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let result = NSMutableAttributedString()

        for (i, msg) in messages.enumerated() {
            let time = Self.timeFmt.string(from: msg.timestamp)

            let timeStr = NSAttributedString(string: "\(time)  ", attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
            let levelStr = NSAttributedString(string: "\(levelTag(msg.level))  ", attributes: [
                .font: font,
                .foregroundColor: levelColor(msg.level)
            ])
            let msgStr = NSAttributedString(string: msg.text, attributes: [
                .font: font,
                .foregroundColor: msgColor(msg.level)
            ])

            result.append(timeStr)
            result.append(levelStr)
            result.append(msgStr)
            if i < messages.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
        }
        return result
    }

    private func levelTag(_ l: LogMessage.Level) -> String {
        switch l {
        case .print:   return "[OUT]"
        case .info:    return "[INF]"
        case .warning: return "[WRN]"
        case .error:   return "[ERR]"
        }
    }

    private func levelColor(_ l: LogMessage.Level) -> NSColor {
        switch l {
        case .print:   return .secondaryLabelColor
        case .info:    return .controlAccentColor
        case .warning: return .systemOrange
        case .error:   return .systemRed
        }
    }

    private func msgColor(_ l: LogMessage.Level) -> NSColor {
        switch l {
        case .error:   return .systemRed
        case .warning: return .systemOrange
        default:       return .labelColor
        }
    }
}
