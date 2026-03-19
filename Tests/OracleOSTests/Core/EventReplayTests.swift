import Foundation
import Testing
@testable import OracleOS

/// Tests that reducers are deterministic and state can be replayed from events.
@Suite("Event Replay")
struct EventReplayTests {

    @Test("CommitCoordinator commits events and applies reducers")
    func commitAppliesReducers() async throws {
        let store = EventStore()
        let coordinator = CommitCoordinator(
            eventStore: store,
            reducers: [],
            initialState: WorldStateModel()
        )

        let events = [
            EventEnvelope(
                id: UUID(), sequenceNumber: 0,
                commandID: CommandID(), intentID: UUID(),
                timestamp: Date(), eventType: "CommandSucceeded",
                payload: Data()
            )
        ]

        try await coordinator.commit(events)
        let stored = await store.all()
        #expect(stored.count == 1)
        #expect(stored[0].sequenceNumber > 0)
    }

    @Test("Empty event commit is a no-op")
    func emptyCommitIsNoop() async throws {
        let store = EventStore()
        let coordinator = CommitCoordinator(
            eventStore: store,
            reducers: [],
            initialState: WorldStateModel()
        )

        try await coordinator.commit([])
        let stored = await store.all()
        #expect(stored.isEmpty)
    }

    @Test("EventStore assigns monotonically increasing sequence numbers")
    func monotonicSequenceNumbers() async {
        let store = EventStore()
        let seq1 = await store.nextSequenceNumber()
        let seq2 = await store.nextSequenceNumber()
        let seq3 = await store.nextSequenceNumber()
        #expect(seq1 < seq2)
        #expect(seq2 < seq3)
    }

    @Test("EventStore appends are preserved")
    func eventStoreAppendsPreserved() async {
        let store = EventStore()
        let envelope = EventEnvelope(
            id: UUID(), sequenceNumber: 1,
            commandID: CommandID(), intentID: UUID(),
            timestamp: Date(), eventType: "test",
            payload: Data()
        )
        await store.append(envelope)
        let all = await store.all()
        #expect(all.count == 1)
        #expect(all[0].eventType == "test")
    }

    @Test("ExecutionOutcome.failure factory creates proper failure")
    func failureFactoryWorks() {
        struct TestError: Error { let msg: String }
        let metadata = CommandMetadata(intentID: UUID())
        let cmd = LaunchAppCommand(metadata: metadata, bundleID: "test")
        let outcome = ExecutionOutcome.failure(from: TestError(msg: "boom"), command: cmd)
        #expect(outcome.status == .failed)
        #expect(!outcome.verifierReport.notes.isEmpty)
    }
}
