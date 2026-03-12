import Foundation

@MainActor
public final class RecoveryEngine {

    private let registry: RecoveryRegistry
    private let selector: RecoveryStrategySelector

    public init(registry: RecoveryRegistry = .live()) {
        self.registry = registry
        selector = RecoveryStrategySelector(registry: registry)
    }

    public func recover(
        failure: FailureClass,
        state: WorldState,
        memoryStore: AppMemoryStore? = nil
    ) async -> RecoveryAttempt {
        let memoryStore = memoryStore ?? AppMemoryStore()
        let orderedStrategies = selector.orderedStrategies(
            for: failure,
            state: state,
            memoryStore: memoryStore
        )

        guard !orderedStrategies.isEmpty else {
            return RecoveryAttempt(
                strategyName: nil,
                preparation: nil,
                message: "No recovery strategy"
            )
        }

        for strategy in orderedStrategies {
            do {
                if let preparation = try await strategy.prepare(
                    failure: failure,
                    state: state,
                    memoryStore: memoryStore
                ) {
                    return RecoveryAttempt(
                        strategyName: strategy.name,
                        preparation: preparation,
                        message: "Prepared recovery strategy \(strategy.name)"
                    )
                }
            } catch {
                if strategy.name == orderedStrategies.last?.name {
                    return RecoveryAttempt(
                        strategyName: strategy.name,
                        preparation: nil,
                        message: error.localizedDescription
                    )
                }
            }
        }

        return RecoveryAttempt(
            strategyName: nil,
            preparation: nil,
            message: "Recovery exhausted"
        )
    }
}
