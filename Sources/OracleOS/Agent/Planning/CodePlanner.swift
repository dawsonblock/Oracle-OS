import Foundation

public final class CodePlanner: @unchecked Sendable {
    public let maxPatchIterations: Int
    public let maxBuildAttempts: Int
    public let maxTestAttempts: Int
    public let directRepairThreshold: Double
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
        directRepairThreshold: Double = 0.7,
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
        self.directRepairThreshold = directRepairThreshold
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
        let enrichedWorldState = WorldState(
            observationHash: worldState.observationHash,
            planningState: worldState.planningState,
            beliefStateID: worldState.beliefStateID,
            observation: worldState.observation,
            repositorySnapshot: snapshot,
            lastAction: worldState.lastAction
        )
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: enrichedWorldState,
                errorSignature: taskContext.goal.description
            )
        )
        let description = taskContext.goal.description.lowercased()
        let projectMemorySignals = memoryInfluence.projectMemorySignals
        let candidatePaths = likelyCandidatePaths(
            taskContext: taskContext,
            snapshot: snapshot,
            memoryInfluence: memoryInfluence
        )
        let isRepairGoal = repairGoal(description)
        let projectMemoryRefs = projectMemorySignals.refs
        let projectMemoryContext = ProjectMemoryPlanningContext(refs: projectMemoryRefs)
        let architectureReview = architectureEngine.review(
            goalDescription: taskContext.goal.description,
            snapshot: snapshot,
            candidatePaths: candidatePaths
        )
        let explorationFallbackReason = "workflow retrieval, stable graph path reuse, and candidate graph reuse were unavailable"

        if let workflowDecision = workflowDecision(
            taskContext: taskContext,
            worldState: worldState,
            projectMemoryRefs: projectMemoryRefs,
            memoryStore: memoryStore
        ) {
            return workflowDecision
        }

        if let graphDecision = graphDecision(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            projectMemoryRefs: projectMemoryRefs,
            projectMemorySignals: projectMemorySignals,
            architectureReview: architectureReview
        ) {
            return graphDecision
        }

        if isRepairGoal,
           let repairDecision = repairDecision(
               taskContext: taskContext,
               snapshot: snapshot,
               projectMemoryRefs: projectMemoryRefs,
               projectMemoryContext: projectMemoryContext,
               projectMemorySignals: projectMemorySignals,
               memoryInfluence: memoryInfluence,
               architectureReview: architectureReview,
               candidatePaths: candidatePaths
           ) {
            return repairDecision
        }

        if description.contains("push") {
            return decision(
                for: "git_push",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason,
                notes: ["git push requested"] + projectMemorySignals.riskSummaries
            )
        }
        if description.contains("commit") {
            return decision(
                for: "git_commit",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("branch") {
            return decision(
                for: "git_branch",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("format") {
            return decision(
                for: "run_formatter",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("lint") {
            return decision(
                for: "run_linter",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("build") || description.contains("compile") {
            return decision(
                for: "run_build",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("test") || description.contains("failing") {
            return decision(
                for: "run_tests",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        return decision(
            for: "read_repository",
            snapshot: snapshot,
            projectMemoryRefs: projectMemoryRefs,
            architectureReview: architectureReview,
            fallbackReason: explorationFallbackReason,
            notes: ["default repository inspection"] + projectMemorySignals.riskSummaries
        )
    }

    private func graphDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore,
        projectMemoryRefs: [ProjectMemoryRef],
        projectMemorySignals: ProjectMemoryPlanningSignals,
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
            worldState: worldState,
            riskPenalty: graphRiskPenalty(
                architectureReview: architectureReview,
                projectMemorySignals: projectMemorySignals
            )
        ),
              let edge = searchResult.edges.first,
              let contract = graphStore.actionContract(for: edge.actionContractID)
        else {
            return candidateGraphDecision(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore,
                projectMemoryRefs: projectMemoryRefs,
                projectMemorySignals: projectMemorySignals,
                architectureReview: architectureReview
            )
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
            fallbackReason: "workflow retrieval did not yield a reusable plan",
            graphSearchDiagnostics: searchResult.diagnostics,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            refactorProposalID: architectureReview.refactorProposal?.id,
            notes: graphNotes(
                prefix: searchResult.reachedGoal ? "stable graph path reaches engineering goal" : "stable graph path improves engineering state",
                diagnostics: searchResult.diagnostics
            )
        )
    }

    private func candidateGraphDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore,
        projectMemoryRefs: [ProjectMemoryRef],
        projectMemorySignals: ProjectMemoryPlanningSignals,
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

        guard let selection = graphPlanner.bestCandidateEdge(
            from: worldState.planningState,
            goal: graphGoal,
            graphStore: graphStore,
            memoryStore: memoryStore,
            worldState: worldState,
            riskPenalty: graphRiskPenalty(
                architectureReview: architectureReview,
                projectMemorySignals: projectMemorySignals
            )
        ),
        let contract = selection.actionContract
        else {
            return nil
        }

        return PlannerDecision(
            agentKind: .code,
            plannerFamily: .code,
            stepPhase: .engineering,
            executionMode: .direct,
            actionContract: contract,
            source: .candidateGraph,
            pathEdgeIDs: [selection.edge.edgeID],
            currentEdgeID: selection.edge.edgeID,
            fallbackReason: "workflow retrieval and stable graph path reuse were unavailable",
            graphSearchDiagnostics: selection.diagnostics,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            refactorProposalID: architectureReview.refactorProposal?.id,
            notes: graphNotes(
                prefix: "candidate graph edge reuse",
                diagnostics: selection.diagnostics
            ) + ["candidate score \(String(format: "%.2f", selection.score))"]
        )
    }

    private func workflowDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        projectMemoryRefs: [ProjectMemoryRef],
        memoryStore: AppMemoryStore
    ) -> PlannerDecision? {
        guard let workflowMatch = workflowRetriever.retrieve(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore
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
        experimentDecision: ExperimentDecision? = nil,
        fallbackReason: String? = nil,
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
            fallbackReason: fallbackReason,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            refactorProposalID: architectureReview.refactorProposal?.id,
            experimentSpec: experimentSpec,
            experimentDecision: experimentDecision,
            notes: notes
        )
    }

    private func repairDecision(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        projectMemoryRefs: [ProjectMemoryRef],
        projectMemoryContext: ProjectMemoryPlanningContext,
        projectMemorySignals: ProjectMemoryPlanningSignals,
        memoryInfluence: MemoryInfluence,
        architectureReview: ArchitectureReview,
        candidatePaths: [String]
    ) -> PlannerDecision? {
        let assessment = assessRepairRouting(
            taskContext: taskContext,
            snapshot: snapshot,
            architectureReview: architectureReview,
            projectMemoryContext: projectMemoryContext,
            projectMemorySignals: projectMemorySignals,
            memoryInfluence: memoryInfluence,
            candidatePaths: candidatePaths
        )

        if assessment.shouldUseExperiments,
           let experimentSpec = experimentSpec(
               taskContext: taskContext,
               snapshot: snapshot,
               architectureReview: architectureReview,
               candidatePaths: candidatePaths,
               assessment: assessment
           ) {
            let primaryPath = experimentSpec.candidates.first?.workspaceRelativePath
            let experimentDecision = ExperimentDecision(
                reason: assessment.experimentReason ?? "low-confidence repair path",
                candidateCount: experimentSpec.candidates.count,
                architectureRiskScore: architectureReview.riskScore
            )
            return decision(
                for: "generate_patch",
                snapshot: snapshot,
                workspaceRelativePath: primaryPath,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                executionMode: .experiment,
                experimentSpec: experimentSpec,
                experimentDecision: experimentDecision,
                fallbackReason: "workflow retrieval, stable graph path reuse, and candidate graph reuse were unavailable",
                notes: [
                    "parallel experiment fanout requested",
                    "direct repair confidence \(String(format: "%.2f", assessment.directRepairConfidence))",
                    "candidate count \(experimentSpec.candidates.count)",
                ] + assessment.reasons + projectMemorySignals.riskSummaries
            )
        }

        let preferredPath = candidatePaths.first
        let constrainedRefactor = taskContext.goal.description.lowercased().contains("refactor")
            && architectureReview.triggered
            && projectMemoryContext.hasArchitectureDecisions
        let skillName = constrainedRefactor ? "search_code" : (preferredPath == nil ? "search_code" : "edit_file")
        let targetNote = preferredPath.map { "memory/query-biased target \($0)" } ?? "code exploration fallback"
        return decision(
            for: skillName,
            snapshot: snapshot,
            workspaceRelativePath: preferredPath,
            projectMemoryRefs: projectMemoryRefs,
            architectureReview: architectureReview,
            fallbackReason: "workflow retrieval, stable graph path reuse, and candidate graph reuse were unavailable",
            notes: [
                targetNote,
                "direct repair confidence \(String(format: "%.2f", assessment.directRepairConfidence))",
            ] + assessment.reasons + projectMemorySignals.riskSummaries
        )
    }

    private func likelyCandidatePaths(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        memoryInfluence: MemoryInfluence
    ) -> [String] {
        var candidates: [String] = []
        if let preferredPath = memoryInfluence.preferredFixPath {
            candidates.append(preferredPath)
        }

        candidates.append(contentsOf: RepositoryQuery.likelyFiles(for: taskContext.goal.description, in: snapshot))
        candidates.append(contentsOf: memoryInfluence.preferredPaths)

        if candidates.isEmpty {
            candidates.append(contentsOf: snapshot.files
                .filter { !$0.isDirectory && $0.path.hasSuffix(".swift") }
                .map(\.path)
                .prefix(3))
        }

        let preferredPaths = Set(memoryInfluence.preferredPaths)
        let avoidedPaths = Set(memoryInfluence.avoidedPaths)

        return orderedUnique(candidates).sorted { lhs, rhs in
            let lhsScore = candidatePathScore(
                path: lhs,
                preferredPaths: preferredPaths,
                avoidedPaths: avoidedPaths
            )
            let rhsScore = candidatePathScore(
                path: rhs,
                preferredPaths: preferredPaths,
                avoidedPaths: avoidedPaths
            )
            if lhsScore == rhsScore {
                return lhs < rhs
            }
            return lhsScore > rhsScore
        }
    }

    private func graphNotes(prefix: String, diagnostics: GraphSearchDiagnostics) -> [String] {
        var notes = [prefix, "explored \(diagnostics.exploredEdgeIDs.count) graph edges"]
        if !diagnostics.rejectedEdgeIDs.isEmpty {
            notes.append("rejected \(diagnostics.rejectedEdgeIDs.count) alternatives")
        }
        if let fallbackReason = diagnostics.fallbackReason {
            notes.append(fallbackReason)
        }
        return notes
    }

    private func experimentSpec(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        architectureReview: ArchitectureReview,
        candidatePaths: [String],
        assessment: RepairRoutingAssessment
    ) -> ExperimentSpec? {
        guard !taskContext.experimentCandidates.isEmpty else {
            return nil
        }

        guard assessment.shouldUseExperiments,
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

    private func assessRepairRouting(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        architectureReview: ArchitectureReview,
        projectMemoryContext: ProjectMemoryPlanningContext,
        projectMemorySignals: ProjectMemoryPlanningSignals,
        memoryInfluence: MemoryInfluence,
        candidatePaths: [String]
    ) -> RepairRoutingAssessment {
        var confidence = 0.45
        var reasons: [String] = []
        let description = taskContext.goal.description.lowercased()
        let preferredPaths = Set(projectMemorySignals.preferredPaths(in: snapshot))
        let avoidedPaths = Set(projectMemorySignals.avoidedPaths(in: snapshot))
        let preferredCandidateCount = candidatePaths.filter { preferredPaths.contains($0) }.count
        let effectiveCandidateCount = preferredCandidateCount == 1 ? 1 : candidatePaths.count

        if effectiveCandidateCount == 1 {
            confidence += 0.25
            reasons.append(preferredCandidateCount == 1 ? "project memory narrowed to one likely target path" : "single likely target path")
        } else if effectiveCandidateCount > 1 {
            confidence -= 0.25
            reasons.append("multiple plausible target paths")
        } else {
            confidence -= 0.15
            reasons.append("no strong target path")
        }

        if projectMemoryContext.hasKnownGoodPatterns {
            confidence += 0.15
            reasons.append("known-good patterns favor direct repair")
        }
        if projectMemoryContext.hasArchitectureDecisions {
            confidence += 0.05
            reasons.append("architecture decisions constrain repair shape")
        }
        if candidatePaths.contains(where: { preferredPaths.contains($0) }) {
            confidence += 0.25
            reasons.append("known-good project memory narrowed the target path")
        }
        if description.contains(".swift") || description.contains(".ts") || description.contains(".js") || description.contains(".py") {
            confidence += 0.1
            reasons.append("goal names an explicit code file")
        }
        if projectMemoryContext.hasRejectedApproaches {
            confidence -= 0.2
            reasons.append("rejected approaches discourage single-path repair")
        }
        if candidatePaths.contains(where: { avoidedPaths.contains($0) }) {
            confidence -= 0.2
            reasons.append("project memory marks this repair path as previously rejected")
        }
        if projectMemoryContext.hasOpenProblems {
            confidence -= 0.15
            reasons.append("open problems suggest unresolved prior attempts")
        }
        if memoryInfluence.shouldPreferExperiments {
            confidence -= 0.1
            reasons.append("memory routing prefers experiment fanout")
        }
        if projectMemorySignals.hasRisks,
           description.contains("push") || description.contains("delete") || description.contains("release") {
            confidence -= 0.1
            reasons.append("risk register warns about this operation class")
        }
        if architectureReview.triggered || architectureReview.riskScore >= 0.5 {
            confidence -= 0.2
            reasons.append("architecture review raises repair risk")
        }
        if description.contains("compare") || description.contains("experiment") {
            confidence -= 0.1
            reasons.append("goal explicitly requests comparison")
        }

        confidence = min(max(confidence, 0), 1)

        let hasExperimentCandidates = !taskContext.experimentCandidates.isEmpty
        let architectureRequiresExperiment = architectureReview.riskScore >= 0.5 && preferredCandidateCount == 0
        let shouldUseExperiments = hasExperimentCandidates && (
            confidence < directRepairThreshold
                || effectiveCandidateCount > 1
                || projectMemoryContext.shouldEscalateToExperiment
                || memoryInfluence.shouldPreferExperiments
                || architectureRequiresExperiment
                || description.contains("compare")
                || description.contains("experiment")
        )

        let experimentReason: String?
        if shouldUseExperiments {
            if projectMemoryContext.hasRejectedApproaches {
                experimentReason = "previous approaches were rejected"
            } else if effectiveCandidateCount > 1 {
                experimentReason = "ambiguous edit target"
            } else if projectMemoryContext.hasOpenProblems {
                experimentReason = "open problem remains unresolved"
            } else if architectureRequiresExperiment {
                experimentReason = "architecture impact is high enough to compare fixes"
            } else {
                experimentReason = "direct repair confidence fell below threshold"
            }
        } else {
            experimentReason = nil
        }

        return RepairRoutingAssessment(
            directRepairConfidence: confidence,
            shouldUseExperiments: shouldUseExperiments,
            experimentReason: experimentReason,
            reasons: reasons
        )
    }

    private func repairGoal(_ description: String) -> Bool {
        description.contains("fix")
            || description.contains("patch")
            || description.contains("repair")
            || description.contains("refactor")
            || description.contains("failing")
            || description.contains("broken")
            || description.contains("error")
    }

    private func candidatePathScore(
        path: String,
        preferredPaths: Set<String>,
        avoidedPaths: Set<String>
    ) -> Int {
        var score = 0
        if preferredPaths.contains(path) {
            score += 2
        }
        if avoidedPaths.contains(path) {
            score -= 2
        }
        return score
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

    private func graphRiskPenalty(
        architectureReview: ArchitectureReview,
        projectMemorySignals: ProjectMemoryPlanningSignals
    ) -> Double {
        let architecturePenalty = architectureReview.riskScore * 0.15
        let projectMemoryPenalty = projectMemorySignals.hasRisks ? 0.1 : 0
        return min(0.25, architecturePenalty + projectMemoryPenalty)
    }
}

private struct RepairRoutingAssessment {
    let directRepairConfidence: Double
    let shouldUseExperiments: Bool
    let experimentReason: String?
    let reasons: [String]
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

private func orderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
}
