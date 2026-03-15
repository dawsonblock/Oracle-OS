import Testing
import Foundation
@testable import OracleOS

@Suite("Runtime Event Bus")
struct RuntimeEventBusTests {

    @Test("Subscriber receives published events")
    func basicPubSub() {
        let bus = RuntimeEventBus()
        var received: [RuntimeEvent] = []
        let lock = NSLock()

        bus.subscribe { event in
            lock.lock()
            received.append(event)
            lock.unlock()
        }

        bus.publish(.taskCreated(TaskEvent(
            taskID: "t1", taskName: "Test", status: "created", source: "test"
        )))
        bus.publish(.actionExecuted(ActionEvent(
            actionName: "click", success: true, durationMs: 42, source: "test"
        )))

        #expect(received.count == 2)
    }

    @Test("Unsubscribed handler stops receiving")
    func unsubscribe() {
        let bus = RuntimeEventBus()
        var count = 0
        let lock = NSLock()

        let id = bus.subscribe { _ in
            lock.lock()
            count += 1
            lock.unlock()
        }
        bus.publish(.stateUpdated(StateUpdateEvent(
            domain: "test", changeDescription: "init", source: "test"
        )))
        #expect(count == 1)

        bus.unsubscribe(id: id)
        bus.publish(.stateUpdated(StateUpdateEvent(
            domain: "test", changeDescription: "second", source: "test"
        )))
        #expect(count == 1)
    }

    @Test("Event log respects max size")
    func eventLogMaxSize() {
        let bus = RuntimeEventBus(maxLogSize: 3)
        for i in 0..<5 {
            bus.publish(.taskCreated(TaskEvent(
                taskID: "t\(i)", taskName: "T\(i)", status: "created", source: "test"
            )))
        }
        #expect(bus.recentEvents().count == 3)
    }

    @Test("EventMetadata populates correctly")
    func metadataFields() {
        let meta = EventMetadata(source: "unit-test")
        #expect(!meta.id.isEmpty)
        #expect(meta.source == "unit-test")
    }

    @Test("Multiple subscribers all receive the same event")
    func multipleSubscribers() {
        let bus = RuntimeEventBus()
        var a = 0, b = 0
        let lock = NSLock()

        bus.subscribe { _ in lock.lock(); a += 1; lock.unlock() }
        bus.subscribe { _ in lock.lock(); b += 1; lock.unlock() }

        bus.publish(.evaluationFinished(EvaluationEvent(
            taskID: "t1", score: 0.9, outcome: "success", source: "test"
        )))

        #expect(a == 1)
        #expect(b == 1)
    }
}
