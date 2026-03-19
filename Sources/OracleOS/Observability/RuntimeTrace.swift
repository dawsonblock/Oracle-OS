import Foundation

/// Records the runtime trace for each intent cycle:
/// Intent → Command → Outcome → Events → Snapshot
///
/// This is the backbone for debugging, replay, eval attribution, and UX inspection.
public struct RuntimeTraceRecord: Sendable, Codable {
    public let traceID: UUID
    public let intentID: UUID
    public let commandID: CommandID?
    public let commandKind: String?
    public let commandType: String?
    public let executionStatus: String?
    public let eventTypes: [String]
    public let eventCount: Int
    public let snapshotID: UUID?
    public let timestamp: Date
    public let durationMs: Int
    public let notes: [String]

    public init(
        traceID: UUID = UUID(),
        intentID: UUID,
        commandID: CommandID? = nil,
        commandKind: String? = nil,
        commandType: String? = nil,
        executionStatus: String? = nil,
        eventTypes: [String] = [],
        eventCount: Int = 0,
        snapshotID: UUID? = nil,
        timestamp: Date = Date(),
        durationMs: Int = 0,
        notes: [String] = []
    ) {
        self.traceID = traceID
        self.intentID = intentID
        self.commandID = commandID
        self.commandKind = commandKind
        self.commandType = commandType
        self.executionStatus = executionStatus
        self.eventTypes = eventTypes
        self.eventCount = eventCount
        self.snapshotID = snapshotID
        self.timestamp = timestamp
        self.durationMs = durationMs
        self.notes = notes
    }
}

/// Collects runtime trace records for inspection and debugging.
public actor RuntimeTraceCollector {
    private var records: [RuntimeTraceRecord] = []
    private let maxRecords: Int

    public init(maxRecords: Int = 1000) {
        self.maxRecords = maxRecords
    }

    public func record(_ trace: RuntimeTraceRecord) {
        records.append(trace)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
    }

    public func allRecords() -> [RuntimeTraceRecord] {
        records
    }

    public func recentRecords(limit: Int = 20) -> [RuntimeTraceRecord] {
        Array(records.suffix(limit))
    }

    public func records(forIntentID id: UUID) -> [RuntimeTraceRecord] {
        records.filter { $0.intentID == id }
    }
}
