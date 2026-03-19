import Foundation

/// Produces intents for the AgentLoop to forward to RuntimeOrchestrator.
/// This is the intake side of the runtime: CLI, controller, MCP, recipes all
/// become IntentSource implementations.
///
/// AgentLoop should only consume intents from this protocol and forward them
/// to IntentAPI.submitIntent. It must not plan, execute, or mutate state.
public protocol IntentSource: Sendable {
    /// Return the next intent to process, or nil if no more work is available.
    func next() async -> Intent?
}

/// An IntentSource backed by a fixed sequence of intents.
public struct FixedIntentSource: IntentSource {
    private let intents: [Intent]
    private let index: ManagedAtomic<Int>

    public init(intents: [Intent]) {
        self.intents = intents
        self.index = ManagedAtomic(0)
    }

    public func next() async -> Intent? {
        let current = index.loadAndIncrement()
        guard current < intents.count else { return nil }
        return intents[current]
    }
}

/// Thread-safe atomic integer for FixedIntentSource.
final class ManagedAtomic<T: Numeric>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ initial: T) {
        self.value = initial
    }

    func loadAndIncrement() -> T {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}
