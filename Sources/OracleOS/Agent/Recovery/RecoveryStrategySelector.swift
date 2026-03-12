import Foundation

@MainActor
public struct RecoveryStrategySelector {
    private let registry: RecoveryRegistry

    public init(registry: RecoveryRegistry) {
        self.registry = registry
    }

    public func orderedStrategies(
        for failure: FailureClass,
        state: WorldState,
        memoryStore: AppMemoryStore?
    ) -> [any RecoveryStrategy] {
        let preferredStrategy = memoryStore.flatMap {
            MemoryRouter(memoryStore: $0).preferredRecoveryStrategy(
                app: state.observation.app ?? "unknown"
            )
        }
        let strategies = registry.strategies(for: failure)
        guard let preferredStrategy else { return strategies }

        return strategies.sorted { lhs, rhs in
            if lhs.name == preferredStrategy { return true }
            if rhs.name == preferredStrategy { return false }
            return lhs.name < rhs.name
        }
    }
}
