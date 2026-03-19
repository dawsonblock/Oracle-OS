import Foundation

public protocol IntentSource: Sendable {
    func next() async -> Intent?
}

@MainActor
public final class AgentLoop {

    private let intake: IntentSource
    private let orchestrator: IntentAPI

    private var running = true

    public init(
        intake: IntentSource,
        orchestrator: IntentAPI
    ) {
        self.intake = intake
        self.orchestrator = orchestrator
    }

    public func run() async {
        while running {
            guard let intent = await intake.next() else {
                continue
            }

            do {
                _ = try await orchestrator.submitIntent(intent)
            } catch {
                // Log but continue - orchestrator handles errors
            }
        }
    }

    public func stop() {
        running = false
    }
}

public final class QueueIntentSource: IntentSource {
    private let queue: AsyncStream<Intent>
    private var iterator: AsyncStream<Intent>.Iterator?

    public init(queue: AsyncStream<Intent>) {
        self.queue = queue
    }

    public func next() async -> Intent? {
        if iterator == nil {
            iterator = queue.makeIterator()
        }
        return await iterator?.next()
    }
}
