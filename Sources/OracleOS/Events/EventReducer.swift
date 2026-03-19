import Foundation

/// Reducers derive committed state from events. They are the ONLY entities that may update WorldState.
///
/// INVARIANTS:
///   - apply() must be a pure function: same events + same state = same output
///   - No file I/O, network access, shell execution, or logging side effects
///   - No learning updates or recovery logic
///   - State can be replayed from events deterministically
public protocol EventReducer: Sendable {
    func apply(events: [EventEnvelope], to state: inout WorldStateModel)
}
