import Foundation

public struct MemoryQuery {

    public static func preferredControl(
        label: String,
        app: String,
        store: AppMemoryStore
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
        store: AppMemoryStore
    ) -> Double {
        store.rankingBias(label: label, app: app)
    }

    public static func preferredRecoveryStrategy(
        app: String,
        store: AppMemoryStore
    ) -> String? {
        store.preferredRecoveryStrategy(app: app)
    }

    public static func preferredFixPath(
        errorSignature: String,
        store: AppMemoryStore
    ) -> String? {
        store.preferredFixPath(errorSignature: errorSignature)
    }

    public static func commandBias(
        category: String,
        workspaceRoot: String,
        store: AppMemoryStore
    ) -> Double {
        store.commandBias(category: category, workspaceRoot: workspaceRoot)
    }
}
