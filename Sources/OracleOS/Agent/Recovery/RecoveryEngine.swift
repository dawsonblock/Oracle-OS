import Foundation

public struct RecoveryAttempt: Sendable {
    public let strategyName: String?
    public let result: ActionResult

    public init(strategyName: String?, result: ActionResult) {
        self.strategyName = strategyName
        self.result = result
    }
}

@MainActor
public final class RecoveryEngine {

    private let registry: RecoveryRegistry

    public init(registry: RecoveryRegistry = .live()) {
        self.registry = registry
    }

    public func recover(
        failure: FailureClass,
        state: WorldState,
        memoryStore: AppMemoryStore? = nil
    ) async -> RecoveryAttempt {
        let preferredStrategy = memoryStore.flatMap {
            MemoryQuery.preferredRecoveryStrategy(app: state.observation.app ?? "unknown", store: $0)
        }
        let orderedStrategies = prioritize(
            strategies: registry.strategies(for: failure),
            preferredStrategy: preferredStrategy
        )

        guard !orderedStrategies.isEmpty else {
            return RecoveryAttempt(
                strategyName: nil,
                result: ActionResult(
                    success: false,
                    verified: false,
                    message: "No recovery strategy",
                    failureClass: failure.rawValue
                )
            )
        }

        for strategy in orderedStrategies {
            do {
                let result = try await strategy.attempt(
                    failure: failure,
                    state: state
                )
                return RecoveryAttempt(strategyName: strategy.name, result: result)
            } catch {
                if strategy.name == orderedStrategies.last?.name {
                    return RecoveryAttempt(
                        strategyName: strategy.name,
                        result: ActionResult(
                            success: false,
                            verified: false,
                            message: error.localizedDescription,
                            failureClass: failure.rawValue
                        )
                    )
                }
            }
        }

        return RecoveryAttempt(
            strategyName: nil,
            result: ActionResult(
                success: false,
                verified: false,
                message: "Recovery exhausted",
                failureClass: failure.rawValue
            )
        )
    }

    private func prioritize(
        strategies: [any RecoveryStrategy],
        preferredStrategy: String?
    ) -> [any RecoveryStrategy] {
        guard let preferredStrategy else { return strategies }
        return strategies.sorted { lhs, rhs in
            if lhs.name == preferredStrategy { return true }
            if rhs.name == preferredStrategy { return false }
            return lhs.name < rhs.name
        }
    }
}
