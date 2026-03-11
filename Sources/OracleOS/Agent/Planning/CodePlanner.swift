import Foundation

public final class CodePlanner: @unchecked Sendable {
    public let maxPatchIterations: Int
    public let maxBuildAttempts: Int
    public let maxTestAttempts: Int
    private let repositoryIndexer: RepositoryIndexer
    private let architectureEngine: ArchitectureEngine
    private let graphPlanner: GraphPlanner
    private let workflowIndex: WorkflowIndex
    private let workflowRetriever: WorkflowRetriever
    private let workflowExecutor: WorkflowExecutor

    public init(
        maxPatchIterations: Int = 5,
        maxBuildAttempts: Int = 5,
        maxTestAttempts: Int = 5,
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        architectureEngine: ArchitectureEngine = ArchitectureEngine(),
        graphPlanner: GraphPlanner = GraphPlanner(),
        workflowIndex: WorkflowIndex = WorkflowIndex(),
        workflowRetriever: WorkflowRetriever = WorkflowRetriever(),
        workflowExecutor: WorkflowExecutor = WorkflowExecutor()
    ) {
        self.maxPatchIterations = maxPatchIterations
        self.maxBuildAttempts = maxBuildAttempts
        self.maxTestAttempts = maxTestAttempts
        self.repositoryIndexer = repositoryIndexer
        self.architectureEngine = architectureEngine
        self.graphPlanner = graphPlanner
        self.workflowIndex = workflowIndex
        self.workflowRetriever = workflowRetriever
        self.workflowExecutor = workflowExecutor
    }

    public func nextStep(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore
    ) -> PlannerDecision? {
        guard let workspaceRoot = taskContext.workspaceRoot else { return nil }
        let snapshot = worldState.repositorySnapshot
            ?? repositoryIndexer.index(workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
        let description = taskContext.goal.description.lowercased()
        let candidatePaths = likelyCandidatePaths(
            taskContext: taskContext,
            snapshot: snapshot,
            memoryStore: memoryStore
        )
        let projectMemoryRefs = projectMemoryRefs(taskContext: taskContext, snapshot: snapshot)
        let projectMemoryContext = ProjectMemoryPlanningContext(refs: projectMemoryRefs)
        let architectureReview = architectureEngine.review(
            goalDescription: taskContext.goal.description,
            snapshot: snapshot,
            candidatePaths: candidatePaths
        )

        if let workflowDecision = workflowDecision(
            taskContext: taskContext,
            worldState: worldState,
            projectMemoryRefs: projectMemoryRefs
        ) {
            return workflowDecision
        }

        if let graphDecision = graphDecision(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            projectMemoryRefs: projectMemoryRefs,
            architectureReview: architectureReview
        ) {
            return graphDecision
        }

        if let experimentSpec = experimentSpec(
            taskContext: taskContext,
            snapshot: snapshot,
            architectureReview: architectureReview,
            projectMemoryContext: projectMemoryContext,
            candidatePaths: candidatePaths
        ) {
            let primaryPath = experimentSpec.candidates.first?.workspaceRelativePath
            return decision(
                for: "generate_patch",
                snapshot: snapshot,
                workspaceRelativePath: primaryPath,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                executionMode: .experiment,
                experimentSpec: experimentSpec,
                notes: [
                    "parallel experiment fanout requested",
                    "candidate count \(experimentSpec.candidates.count)",
                    projectMemoryContext.experimentBiasNote,
                ]
            )
        }

        if description.contains("push") {
            return decision(
                for: "git_push",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview
            )
        }
        if description.contains("commit") {
            return decision(
                for: "git_commit",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview
            )
        }
        if description.contains("branch") {
            return decision(
                for: "git_branch",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview
            )
        }
        if description.contains("format") {
            return decision(
                for: "run_formatter",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview
            )
        }
        if description.contains("lint") {
            return decision(
                for: "run_linter",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview
            )
        }
        if description.contains("build") || description.contains("compile") {
            return decision(
                for: "run_build",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview
            )
        }
        if description.contains("test") || description.contains("failing") {
            return decision(
                for: "run_tests",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview
            )
        }
        if description.contains("fix") || description.contains("patch") || description.contains("refactor") {
            let preferredPath = candidatePaths.first
            let note = preferredPath.map { "memory/query-biased target \($0)" } ?? "code exploration fallback"
            let constrainedRefactor = description.contains("refactor")
                && architectureReview.triggered
                && projectMemoryContext.hasArchitectureDecisions
            let skillName = constrainedRefactor ? "search_code" : (preferredPath == nil ? "search_code" : "edit_file")
            return decision(
                for: skillName,
                snapshot: snapshot,
                workspaceRelativePath: preferredPath,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                notes: [note, projectMemoryContext.planningBiasNote]
            )
        }

        return decision(
            for: "read_repository",
            snapshot: snapshot,
            projectMemoryRefs: projectMemoryRefs,
            architectureReview: architectureReview,
            notes: ["default repository inspection"]
        )
    }

    private func graphDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore,
        projectMemoryRefs: [ProjectMemoryRef],
        architectureReview: ArchitectureReview
    ) -> PlannerDecision? {
        let graphGoal = Goal(
            description: taskContext.goal.description,
            targetApp: taskContext.goal.targetApp,
            targetDomain: taskContext.goal.targetDomain,
            targetTaskPhase: taskContext.goal.targetTaskPhase,
            workspaceRoot: taskContext.goal.workspaceRoot,
            preferredAgentKind: .code
        )
        guard let searchResult = graphPlanner.search(
            from: worldState.planningState,
            goal: graphGoal,
            graphStore: graphStore,
            memoryStore: memoryStore,
            worldState: worldState
        ),
              let edge = searchResult.edges.first,
              let contract = graphStore.actionContract(for: edge.actionContractID)
        else {
            return nil
        }

        return PlannerDecision(
            agentKind: .code,
            plannerFamily: .code,
            stepPhase: .engineering,
            executionMode: .direct,
            actionContract: contract,
            source: .stableGraph,
            pathEdgeIDs: searchResult.edges.map(\.edgeID),
            currentEdgeID: edge.edgeID,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            refactorProposalID: architectureReview.refactorProposal?.id,
            notes: [
                searchResult.reachedGoal ? "graph path reaches engineering goal" : "graph-backed engineering path",
            ]
        )
    }

    private func workflowDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        projectMemoryRefs: [ProjectMemoryRef]
    ) -> PlannerDecision? {
        guard let workflowMatch = workflowRetriever.retrieve(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex
        ) else {
            return nil
        }
        return workflowExecutor.nextDecision(
            match: workflowMatch,
            plannerFamily: .code,
            sourceNotes: projectMemoryRefs.isEmpty ? [] : ["project memory informed workflow retrieval"]
        )
    }

    private func decision(
        for skillName: String,
        snapshot: RepositorySnapshot,
        workspaceRelativePath: String? = nil,
        projectMemoryRefs: [ProjectMemoryRef] = [],
        architectureReview: ArchitectureReview = ArchitectureReview(
            triggered: false,
            affectedModules: [],
            findings: [],
            refactorProposal: nil,
            riskScore: 0
        ),
        executionMode: PlannerExecutionMode = .direct,
        experimentSpec: ExperimentSpec? = nil,
        notes: [String] = ["bounded code exploration"]
    ) -> PlannerDecision? {
        let contract = ActionContract(
            id: [
                "code",
                skillName,
                snapshot.buildTool.rawValue,
                snapshot.activeBranch ?? "detached",
                workspaceRelativePath ?? "none",
            ].joined(separator: "|"),
            agentKind: .code,
            skillName: skillName,
            targetRole: nil,
            targetLabel: nil,
            locatorStrategy: "code-planner",
            workspaceRelativePath: workspaceRelativePath,
            commandCategory: commandCategory(for: skillName)?.rawValue,
            plannerFamily: PlannerFamily.code.rawValue
        )
        return PlannerDecision(
            agentKind: .code,
            skillName: skillName,
            plannerFamily: .code,
            stepPhase: .engineering,
            executionMode: executionMode,
            actionContract: contract,
            source: .exploration,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            refactorProposalID: architectureReview.refactorProposal?.id,
            experimentSpec: experimentSpec,
            notes: notes
        )
    }

    private func likelyCandidatePaths(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        memoryStore: AppMemoryStore
    ) -> [String] {
        if let preferredPath = MemoryQuery.preferredFixPath(
            errorSignature: taskContext.goal.description,
            store: memoryStore
        ) {
            return [preferredPath]
        }

        let files = RepositoryQuery.likelyFiles(for: taskContext.goal.description, in: snapshot)
        if !files.isEmpty {
            return files
        }

        return snapshot.files
            .filter { !$0.isDirectory && $0.path.hasSuffix(".swift") }
            .map(\.path)
            .prefix(3)
            .map { $0 }
    }

    private func projectMemoryRefs(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot
    ) -> [ProjectMemoryRef] {
        guard let workspaceRoot = taskContext.workspaceRoot else {
            return []
        }
        do {
            let store = try ProjectMemoryStore(projectRootURL: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
            return ProjectMemoryQuery.relevantRecords(
                goalDescription: taskContext.goal.description,
                snapshot: snapshot,
                store: store
            )
        } catch {
            return []
        }
    }

    private func experimentSpec(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        architectureReview: ArchitectureReview,
        projectMemoryContext: ProjectMemoryPlanningContext,
        candidatePaths: [String]
    ) -> ExperimentSpec? {
        guard !taskContext.experimentCandidates.isEmpty else {
            return nil
        }

        let shouldFanOut = architectureReview.triggered
            || projectMemoryContext.shouldEscalateToExperiment
            || taskContext.goal.description.lowercased().contains("experiment")
            || taskContext.goal.description.lowercased().contains("compare")
            || taskContext.goal.description.lowercased().contains("fix")
            || candidatePaths.count > 1

        guard shouldFanOut,
              let workspaceRoot = taskContext.workspaceRoot
        else {
            return nil
        }

        let workspaceURL = URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        return ExperimentSpec(
            goalDescription: taskContext.goal.description,
            workspaceRoot: workspaceRoot,
            candidates: Array(taskContext.experimentCandidates.prefix(taskContext.maxExperimentCandidates)),
            buildCommand: BuildToolDetector.defaultBuildCommand(for: snapshot.buildTool, workspaceRoot: workspaceURL),
            testCommand: BuildToolDetector.defaultTestCommand(for: snapshot.buildTool, workspaceRoot: workspaceURL)
        )
    }

    private func commandCategory(for skillName: String) -> CodeCommandCategory? {
        switch skillName {
        case "read_repository":
            .indexRepository
        case "search_code":
            .searchCode
        case "open_file":
            .openFile
        case "edit_file":
            .editFile
        case "write_file":
            .writeFile
        case "generate_patch":
            .generatePatch
        case "run_build":
            .build
        case "run_tests":
            .test
        case "run_formatter":
            .formatter
        case "run_linter":
            .linter
        case "git_status":
            .gitStatus
        case "git_branch":
            .gitBranch
        case "git_commit":
            .gitCommit
        case "git_push":
            .gitPush
        default:
            nil
        }
    }
}

private struct ProjectMemoryPlanningContext {
    let refs: [ProjectMemoryRef]

    var hasRejectedApproaches: Bool {
        refs.contains(where: { $0.kind == .rejectedApproach })
    }

    var hasKnownGoodPatterns: Bool {
        refs.contains(where: { $0.kind == .knownGoodPattern })
    }

    var hasOpenProblems: Bool {
        refs.contains(where: { $0.kind == .openProblem })
    }

    var hasArchitectureDecisions: Bool {
        refs.contains(where: { $0.kind == .architectureDecision })
    }

    var shouldEscalateToExperiment: Bool {
        hasRejectedApproaches || hasOpenProblems
    }

    var experimentBiasNote: String {
        if hasRejectedApproaches {
            return "rejected approaches bias toward experiment fanout"
        }
        if hasOpenProblems {
            return "open problems bias toward experiment fanout"
        }
        return "experiments available"
    }

    var planningBiasNote: String {
        if hasKnownGoodPatterns {
            return "known-good patterns increased direct repair preference"
        }
        if hasArchitectureDecisions {
            return "architecture decisions constrained repair path"
        }
        return "project memory context available"
    }
}
