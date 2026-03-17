import Foundation
/// Replays a cycle from event history.
public struct EventReplay {
    private let eventStore: EventStore
    public init(eventStore: EventStore) { self.eventStore = eventStore }
    public func replay(cycleID: UUID) async throws -> Timeline {
        let events = await eventStore.all()
        return TimelineBuilder().build(from: events)
    }
}
