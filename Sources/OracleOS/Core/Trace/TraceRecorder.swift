import Foundation

@MainActor
public final class TraceRecorder {

    public static let shared = TraceRecorder()

    public let sessionID: String
    public let store = TraceStore()

    private var events: [TraceEvent] = []

    public init() {
        self.sessionID = UUID().uuidString
    }

    @discardableResult
    public func record(_ event: TraceEvent) -> URL? {
        events.append(event)
        return try? store.append(event)
    }

    public func dump() -> [TraceEvent] {
        events
    }
}
