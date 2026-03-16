import SwiftUI
import AppKit

struct LogView: View {
    @Environment(AppState.self) private var state
    @State private var filterLevel: LogMessage.Level? = nil

    private var messages: [LogMessage] {
        guard let level = filterLevel else { return state.logMessages }
        return state.logMessages.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
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

            LogTextView(messages: messages)
        }
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
