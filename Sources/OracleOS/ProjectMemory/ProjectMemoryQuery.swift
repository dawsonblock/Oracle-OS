import Foundation

public enum ProjectMemoryQuery {
    public static func relevantRecords(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        limit: Int = 6
    ) -> [ProjectMemoryRef] {
        store.syncIndex()
        let modules = modulesForSnapshot(snapshot)
        return store.query(
            text: goalDescription,
            modules: modules,
            kinds: [.architectureDecision, .openProblem, .rejectedApproach, .knownGoodPattern],
            limit: limit
        )
    }

    public static func modulesForSnapshot(_ snapshot: RepositorySnapshot) -> [String] {
        let modules = Set(snapshot.files.compactMap { file -> String? in
            guard !file.isDirectory else { return nil }
            return ArchitectureModuleGraph.moduleName(for: file.path)
        })
        return Array(modules).sorted()
    }
}
