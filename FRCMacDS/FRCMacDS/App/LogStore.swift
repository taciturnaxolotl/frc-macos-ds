import Foundation

struct LogSession: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    let teamNumber: Int
    var messages: [SavedLogMessage]

    var displayName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, h:mm:ss a"
        return fmt.string(from: startDate)
    }
}

struct SavedLogMessage: Codable {
    let timestamp: Date
    let level: Int  // 0=info, 1=warning, 2=error, 3=print
    let text: String

    init(_ msg: LogMessage) {
        self.timestamp = msg.timestamp
        switch msg.level {
        case .info:    self.level = 0
        case .warning: self.level = 1
        case .error:   self.level = 2
        case .print:   self.level = 3
        }
        self.text = msg.text
    }

    func toLogMessage() -> LogMessage {
        let lvl: LogMessage.Level
        switch level {
        case 0: lvl = .info
        case 1: lvl = .warning
        case 2: lvl = .error
        default: lvl = .print
        }
        return LogMessage(timestamp: timestamp, level: lvl, text: text)
    }
}

final class LogStore {
    static let shared = LogStore()

    private let logsDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logsDir = appSupport.appendingPathComponent("FRCMacDS/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    func save(_ session: LogSession) {
        guard !session.messages.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        let file = logsDir.appendingPathComponent("\(session.id.uuidString).json")
        try? data.write(to: file, options: .atomic)
    }

    func listSessions() -> [LogSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> LogSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                // Only decode metadata (id, startDate, teamNumber, message count)
                return try? decoder.decode(LogSession.self, from: data)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    func loadSession(id: UUID) -> LogSession? {
        let file = logsDir.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LogSession.self, from: data)
    }

    func deleteSession(id: UUID) {
        let file = logsDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }
}
