import Foundation

public struct MemoryQuery {

    public static func preferredControl(
        label: String,
        app: String,
        store: StrategyMemory
    ) -> KnownControl? {

        let controls = store.controlsForApp(app)

        return controls
            .filter { $0.label?.lowercased() == label.lowercased() }
            .sorted { $0.successCount > $1.successCount }
            .first
    }

    public static func rankingBias(
        label: String?,
        app: String?,
        store: StrategyMemory
    ) -> Double {
        store.rankingBias(label: label, app: app)
    }

    public static func preferredRecoveryStrategy(
        app: String,
        store: StrategyMemory
    ) -> String? {
        store.preferredRecoveryStrategy(app: app)
    }

    public static func preferredFixPath(
        errorSignature: String,
        store: StrategyMemory
    ) -> String? {
        store.preferredFixPath(errorSignature: errorSignature)
    }

    public static func commandBias(
        category: String,
        workspaceRoot: String,
        store: StrategyMemory
    ) -> Double {
        store.commandBias(category: category, workspaceRoot: workspaceRoot)
    }
}
