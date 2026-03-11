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
}
