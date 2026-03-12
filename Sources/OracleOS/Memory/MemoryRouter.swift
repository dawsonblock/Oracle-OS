import Foundation

public struct MemoryRouter {
    private let executionStore: ExecutionMemoryStore?
    private let patternStore: PatternMemoryStore?

    public init(memoryStore: AppMemoryStore? = nil) {
        self.executionStore = memoryStore.map(ExecutionMemoryStore.init(store:))
        self.patternStore = memoryStore.map(PatternMemoryStore.init(store:))
    }

    public func influence(for context: MemoryQueryContext) -> MemoryInfluence {
        let executionBias = executionStore?.rankingBias(
            label: context.label,
            app: context.app
        ) ?? 0
        let commandBias = patternStore?.commandBias(
            category: context.commandCategory,
            workspaceRoot: context.workspaceRoot
        ) ?? 0
        let preferredFixPath = patternStore?.preferredFixPath(
            errorSignature: context.errorSignature ?? context.goalDescription
        )
        let preferredRecoveryStrategy = context.app.flatMap {
            executionStore?.preferredRecoveryStrategy(app: $0)
        }

        let projectSignals = projectMemorySignals(for: context)
        let preferredPaths = context.repositorySnapshot.map {
            projectSignals.preferredPaths(in: $0)
        } ?? []
        let avoidedPaths = context.repositorySnapshot.map {
            projectSignals.avoidedPaths(in: $0)
        } ?? []

        var notes: [String] = []
        var evidence: [MemoryEvidence] = []

        if executionBias > 0 {
            notes.append("execution memory biased ranked selection")
            evidence.append(
                MemoryEvidence(
                    tier: .execution,
                    summary: "repeated successful control use",
                    confidence: executionBias
                )
            )
        }

        if commandBias > 0 {
            notes.append("pattern memory biased command reuse")
            evidence.append(
                MemoryEvidence(
                    tier: .pattern,
                    summary: "repeated successful command use",
                    confidence: commandBias
                )
            )
        }

        if let preferredFixPath {
            notes.append("pattern memory preferred \(preferredFixPath)")
            evidence.append(
                MemoryEvidence(
                    tier: .pattern,
                    summary: "preferred fix path \(preferredFixPath)",
                    confidence: 0.5
                )
            )
        }

        if !projectSignals.refs.isEmpty {
            notes.append("project memory returned \(projectSignals.refs.count) relevant records")
            evidence.append(
                MemoryEvidence(
                    tier: .project,
                    summary: "project memory planning signals",
                    sourceRefs: projectSignals.refs.map(\.path),
                    confidence: min(1, Double(projectSignals.refs.count) * 0.1)
                )
            )
        }

        let shouldPreferExperiments = projectSignals.hasRejectedApproaches || projectSignals.hasOpenProblems
        let riskPenalty = projectSignals.hasRisks ? 0.1 : 0

        return MemoryInfluence(
            executionRankingBias: executionBias,
            commandBias: commandBias,
            preferredFixPath: preferredFixPath,
            preferredRecoveryStrategy: preferredRecoveryStrategy,
            projectMemorySignals: projectSignals,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths,
            shouldPreferExperiments: shouldPreferExperiments,
            riskPenalty: riskPenalty,
            notes: notes,
            evidence: evidence
        )
    }

    public func rankingBias(
        label: String?,
        app: String?,
        goalDescription: String = "",
        repositorySnapshot: RepositorySnapshot? = nil,
        planningState: PlanningState? = nil
    ) -> Double {
        influence(
            for: MemoryQueryContext(
                goalDescription: goalDescription,
                app: app,
                label: label,
                repositorySnapshot: repositorySnapshot,
                planningState: planningState
            )
        ).executionRankingBias
    }

    public func preferredRecoveryStrategy(
        app: String
    ) -> String? {
        influence(
            for: MemoryQueryContext(app: app)
        ).preferredRecoveryStrategy
    }

    public func preferredFixPath(
        errorSignature: String?,
        workspaceRoot: String? = nil,
        repositorySnapshot: RepositorySnapshot? = nil
    ) -> String? {
        influence(
            for: MemoryQueryContext(
                goalDescription: errorSignature ?? "",
                workspaceRoot: workspaceRoot,
                errorSignature: errorSignature,
                repositorySnapshot: repositorySnapshot
            )
        ).preferredFixPath
    }

    public func commandBias(
        category: String?,
        workspaceRoot: String?,
        repositorySnapshot: RepositorySnapshot? = nil
    ) -> Double {
        let influence = influence(
            for: MemoryQueryContext(
                workspaceRoot: workspaceRoot,
                commandCategory: category,
                repositorySnapshot: repositorySnapshot
            )
        )
        return influence.commandBias
    }

    private func projectMemorySignals(
        for context: MemoryQueryContext
    ) -> ProjectMemoryPlanningSignals {
        guard let workspaceRoot = context.workspaceRoot,
              let snapshot = context.repositorySnapshot,
              (context.agentKind == .code || context.agentKind == .mixed || context.agentKind == nil)
        else {
            return ProjectMemoryPlanningSignals()
        }

        do {
            let store = try ProjectMemoryStore(
                projectRootURL: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
            )
            return ProjectMemoryQuery.planningSignals(
                goalDescription: context.goalDescription,
                snapshot: snapshot,
                store: store
            )
        } catch {
            return ProjectMemoryPlanningSignals()
        }
    }
}
