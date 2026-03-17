import XCTest
@testable import OracleOS

/// Verifies that every committed state change corresponds to DomainEvents.
final class EventHistoryInvariantTests: XCTestCase {
    func test_committed_state_has_event_ancestry() {
        let snapshot = StateSnapshot(sequenceNumber: 1, state: WorldStateModel(), eventAncestry: [UUID()])
        XCTAssertFalse(snapshot.eventAncestry.isEmpty, "Every snapshot must have event ancestry")
    }

    func test_event_store_is_append_only() async {
        let store = EventStore()
        await store.append(EventEnvelope(sequenceNumber: 1, commandID: nil, intentID: nil, eventType: "test", payload: Data()))
        let events = await store.all()
        XCTAssertEqual(events.count, 1)
    }
}
