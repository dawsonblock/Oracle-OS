import Foundation

/// The ONLY entity that may write committed state in Oracle-OS.
///
/// Pipeline: wrap events in numbered envelopes → append to event store → apply reducers → publish snapshot.
///
/// INVARIANTS:
///   - No state write may bypass CommitCoordinator
///   - Reducers are the only entities that derive state from events
///   - CommitCoordinator does NOT perform planning, recovery, learning, or business logic
public actor CommitCoordinator {
    private let eventStore: EventStore
    private var reducers: [any EventReducer]
    private(set) var currentState: WorldStateModel

    public init(eventStore: EventStore, reducers: [any EventReducer], initialState: WorldStateModel = WorldStateModel()) {
        self.eventStore = eventStore
        self.reducers = reducers
        self.currentState = initialState
    }

    /// Commit events to the event store and apply reducers to derive new state.
    /// This is the single legal state mutation path in the runtime.
    public func commit(_ envelopes: [EventEnvelope]) async throws {
        guard !envelopes.isEmpty else { return }

        var numberedEnvelopes = envelopes
        for i in 0..<numberedEnvelopes.count {
            let seq = await eventStore.nextSequenceNumber()
            let old = numberedEnvelopes[i]
            numberedEnvelopes[i] = EventEnvelope(
                id: old.id,
                sequenceNumber: seq,
                commandID: old.commandID,
                intentID: old.intentID,
                timestamp: old.timestamp,
                eventType: old.eventType,
                payload: old.payload
            )
        }

        await eventStore.append(contentsOf: numberedEnvelopes)
        for reducer in reducers {
            reducer.apply(events: numberedEnvelopes, to: &currentState)
        }
    }

    /// Returns a read-only copy of the current state to prevent direct mutation.
    public func snapshot() -> WorldModelSnapshot {
        return currentState.snapshot
    }

    /// Register additional reducers (e.g. during runtime setup).
    public func addReducer(_ reducer: any EventReducer) {
        reducers.append(reducer)
    }
}
