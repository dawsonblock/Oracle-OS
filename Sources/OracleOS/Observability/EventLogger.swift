import Foundation

/// Writes event envelopes to a JSONL file for offline debugging and replay.
///
/// Each line contains:
///   - intent ID
///   - command ID
///   - event type
///   - timestamp
///   - outcome status
///   - state delta summary
public actor EventLogger {
    private let fileURL: URL
    private let encoder: JSONEncoder

    public init(directory: URL? = nil) {
        let dir = directory ?? EventLogger.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("events.jsonl")
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    /// Log an event envelope to the JSONL file.
    public func log(_ envelope: EventEnvelope) {
        let entry = EventLogEntry(
            intentID: envelope.intentID?.uuidString ?? "unknown",
            commandID: envelope.commandID?.description ?? "unknown",
            eventType: envelope.eventType,
            timestamp: envelope.timestamp,
            sequenceNumber: envelope.sequenceNumber
        )
        guard let data = try? encoder.encode(entry),
              let line = String(data: data, encoding: .utf8) else { return }

        let lineData = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                handle.closeFile()
            }
        } else {
            try? lineData.write(to: fileURL)
        }
    }

    /// Log a batch of event envelopes.
    public func log(_ envelopes: [EventEnvelope]) {
        for envelope in envelopes {
            log(envelope)
        }
    }

    private static func defaultDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/OracleOS/logs", isDirectory: true)
    }
}

private struct EventLogEntry: Codable {
    let intentID: String
    let commandID: String
    let eventType: String
    let timestamp: Date
    let sequenceNumber: Int
}
