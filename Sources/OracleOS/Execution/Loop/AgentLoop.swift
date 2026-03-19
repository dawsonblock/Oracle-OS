import Foundation

@MainActor
public final class AgentLoop {
    private let intake: any IntentSource
    private let orchestrator: any IntentAPI
    private var running = true

    public init(
        intake: any IntentSource,
        orchestrator: any IntentAPI
    ) {
        self.intake = intake
        self.orchestrator = orchestrator
    }

    public func stop() {
        running = false
    }
}
