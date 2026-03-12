import Foundation

public struct RecoverySelection: @unchecked Sendable {
    public let orderedStrategies: [any RecoveryStrategy]
    public let promptDiagnostics: PromptDiagnostics?

    public init(
        orderedStrategies: [any RecoveryStrategy],
        promptDiagnostics: PromptDiagnostics? = nil
    ) {
        self.orderedStrategies = orderedStrategies
        self.promptDiagnostics = promptDiagnostics
    }
}

@MainActor
public struct RecoveryStrategySelector {
    private let registry: RecoveryRegistry
    private let promptEngine: PromptEngine

    public init(
        registry: RecoveryRegistry,
        promptEngine: PromptEngine = PromptEngine()
    ) {
        self.registry = registry
        self.promptEngine = promptEngine
    }

    public func orderedStrategies(
        for failure: FailureClass,
        state: WorldState,
        memoryStore: AppMemoryStore?
    ) -> [any RecoveryStrategy] {
        select(
            for: failure,
            state: state,
            memoryStore: memoryStore
        ).orderedStrategies
    }

    public func select(
        for failure: FailureClass,
        state: WorldState,
        memoryStore: AppMemoryStore?
    ) -> RecoverySelection {
        let preferredStrategy = memoryStore.flatMap {
            MemoryRouter(memoryStore: $0).preferredRecoveryStrategy(
                app: state.observation.app ?? "unknown"
            )
        }
        let strategies = registry.strategies(for: failure)
        let orderedStrategies: [any RecoveryStrategy]
        if let preferredStrategy {
            orderedStrategies = strategies.sorted { lhs, rhs in
                if lhs.name == preferredStrategy { return true }
                if rhs.name == preferredStrategy { return false }
                return lhs.name < rhs.name
            }
        } else {
            orderedStrategies = strategies
        }

        let promptDiagnostics = promptEngine.recoverySelection(
            failure: failure,
            state: state,
            orderedStrategies: orderedStrategies.map(\.name),
            preferredStrategy: preferredStrategy
        ).diagnostics

        return RecoverySelection(
            orderedStrategies: orderedStrategies,
            promptDiagnostics: promptDiagnostics
        )
    }
}
