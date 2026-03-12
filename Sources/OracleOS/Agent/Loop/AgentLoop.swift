import Foundation

// AgentLoop is the authoritative runtime spine for orchestration only.
// It may observe state, ask planners for structure, invoke policy/execution,
// coordinate recovery, and terminate runs. It must not absorb local ranking,
// patch scoring, experiment result comparison, or direct world mutation logic.
@MainActor
public final class AgentLoop {
    private struct RunState {
        var latestWorldState: WorldState?
        var lastAction: ActionIntent?
        var diagnostics = LoopDiagnostics.empty
        var budgetState = LoopBudgetState()
    }

    private let observationProvider: any ObservationProvider
    private let executionDriver: any AgentExecutionDriver
    private let stateAbstraction: StateAbstraction
    private let planner: Planner
    private let graphStore: GraphStore
    private let policyEngine: PolicyEngine
    private let recoveryEngine: RecoveryEngine
    private let memoryStore: AppMemoryStore
    private let skillRegistry: SkillRegistry
    private let repositoryIndexer: RepositoryIndexer
    private let projectMemoryCoordinator: LoopProjectMemoryCoordinator
    private let experimentCoordinator: LoopExperimentCoordinator

    public init(
        observationProvider: any ObservationProvider,
        executionDriver: any AgentExecutionDriver,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        planner: Planner = Planner(),
        graphStore: GraphStore = GraphStore(),
        policyEngine: PolicyEngine = PolicyEngine(),
        recoveryEngine: RecoveryEngine = RecoveryEngine(),
        memoryStore: AppMemoryStore = AppMemoryStore(),
        skillRegistry: SkillRegistry = .live(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        experimentManager: ExperimentManager = ExperimentManager()
    ) {
        self.observationProvider = observationProvider
        self.executionDriver = executionDriver
        self.stateAbstraction = stateAbstraction
        self.planner = planner
        self.graphStore = graphStore
        self.policyEngine = policyEngine
        self.recoveryEngine = recoveryEngine
        self.memoryStore = memoryStore
        self.skillRegistry = skillRegistry
        self.repositoryIndexer = repositoryIndexer

        let projectMemoryCoordinator = LoopProjectMemoryCoordinator(memoryStore: memoryStore)
        self.projectMemoryCoordinator = projectMemoryCoordinator
        self.experimentCoordinator = LoopExperimentCoordinator(
            experimentManager: experimentManager,
            executionDriver: executionDriver,
            observationProvider: observationProvider,
            stateAbstraction: stateAbstraction,
            recoveryEngine: recoveryEngine,
            memoryStore: memoryStore,
            repositoryIndexer: repositoryIndexer,
            projectMemoryCoordinator: projectMemoryCoordinator
        )
    }

    @discardableResult
    public func run(
        goal: Goal,
        budget: LoopBudget = LoopBudget(),
        surface: RuntimeSurface = .recipe
    ) async -> LoopOutcome {
        planner.setGoal(goal)
        let taskContext = TaskContext.from(
            goal: goal,
            workspaceRoot: goal.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )

        var runState = RunState()

        for stepIndex in 0..<budget.maxSteps {
            let worldState = captureWorldState(
                lastAction: runState.lastAction,
                taskContext: taskContext
            )
            runState.latestWorldState = worldState

            if planner.goalReached(state: worldState.planningState) {
                return finalize(
                    reason: .goalAchieved,
                    finalWorldState: worldState,
                    steps: stepIndex,
                    lastFailure: nil,
                    decision: nil,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            guard let decision = planner.nextStep(
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore
            ) else {
                return finalize(
                    reason: .noViablePlan,
                    finalWorldState: worldState,
                    steps: stepIndex,
                    lastFailure: nil,
                    decision: nil,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            if let budgetReason = runState.budgetState.registerPlannerSource(
                decision.source,
                budget: budget
            ) {
                runState.diagnostics.recordDecision(
                    stepIndex: stepIndex,
                    decision: decision,
                    success: false,
                    notes: decision.notes + ["exploration budget exceeded"]
                )
                return finalize(
                    reason: budgetReason,
                    finalWorldState: worldState,
                    steps: stepIndex,
                    lastFailure: nil,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            let loopTermination = await handleDecision(
                decision,
                stepIndex: stepIndex,
                worldState: worldState,
                taskContext: taskContext,
                budget: budget,
                surface: surface,
                runState: &runState
            )
            if let outcome = loopTermination.outcome {
                return outcome
            }
        }

        return finalize(
            reason: .maxSteps,
            finalWorldState: runState.latestWorldState,
            steps: budget.maxSteps,
            lastFailure: nil,
            decision: nil,
            taskContext: taskContext,
            runState: runState
        )
    }

    public func run(goal: String, state: WorldState) async {
        let interpretedGoal = planner.interpretGoal(goal)
        planner.setGoal(interpretedGoal)
        _ = planner.nextStep(worldState: state, graphStore: graphStore)
    }

    private func handleDecision(
        _ decision: PlannerDecision,
        stepIndex: Int,
        worldState: WorldState,
        taskContext: TaskContext,
        budget: LoopBudget,
        surface: RuntimeSurface,
        runState: inout RunState
    ) async -> LoopTermination {
        if decision.executionMode == .experiment,
           let experimentSpec = decision.experimentSpec
        {
            if let outcome = await experimentCoordinator.handle(
                decision: decision,
                experimentSpec: experimentSpec,
                taskContext: taskContext,
                worldState: worldState,
                budgetState: &runState.budgetState,
                step: stepIndex,
                budget: budget,
                diagnostics: &runState.diagnostics
            ) {
                return .finished(outcome)
            }
            return .continueRunning
        }

        let prepared: SkillResolution
        do {
            prepared = try prepareAction(
                decision: decision,
                state: worldState,
                taskContext: taskContext
            )
        } catch let error as SkillResolutionError {
            return await handlePreparationFailure(
                failure: error.failureClass,
                decision: decision,
                worldState: worldState,
                stepIndex: stepIndex,
                taskContext: taskContext,
                budget: budget,
                surface: surface,
                runState: &runState
            )
        } catch let error as CodeSkillResolutionError {
            return await handlePreparationFailure(
                failure: error.failureClass,
                decision: decision,
                worldState: worldState,
                stepIndex: stepIndex,
                taskContext: taskContext,
                budget: budget,
                surface: surface,
                runState: &runState
            )
        } catch {
            return .finished(
                finalize(
                    reason: .unrecoverableFailure,
                    finalWorldState: worldState,
                    steps: stepIndex + 1,
                    lastFailure: .actionFailed,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            )
        }

        if precheckPolicy(
            prepared: prepared,
            surface: surface,
            stepIndex: stepIndex,
            decision: decision,
            runState: &runState
        ) {
            return .finished(
                finalize(
                    reason: .policyBlocked,
                    finalWorldState: worldState,
                    steps: stepIndex,
                    lastFailure: nil,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            )
        }

        return await executePreparedDecision(
            prepared,
            decision: decision,
            stepIndex: stepIndex,
            worldState: worldState,
            taskContext: taskContext,
            budget: budget,
            surface: surface,
            runState: &runState
        )
    }

    private func precheckPolicy(
        prepared: SkillResolution,
        surface: RuntimeSurface,
        stepIndex: Int,
        decision: PlannerDecision,
        runState: inout RunState
    ) -> Bool {
        let policyDecision = policyEngine.evaluate(
            intent: prepared.intent,
            context: PolicyEvaluationContext(
                surface: surface,
                toolName: "agent_loop",
                appName: prepared.intent.app,
                agentKind: prepared.intent.agentKind,
                workspaceRoot: prepared.intent.workspaceRoot,
                workspaceRelativePath: prepared.intent.workspaceRelativePath,
                commandCategory: prepared.intent.commandCategory
            )
        )

        guard policyDecision.blockedByPolicy || policyDecision.requiresApproval else {
            return false
        }

        runState.diagnostics.recordDecision(
            stepIndex: stepIndex,
            decision: decision,
            success: false,
            failure: .actionFailed,
            notes: decision.notes + ["policy precheck blocked execution"]
        )
        return true
    }

    private func executePreparedDecision(
        _ prepared: SkillResolution,
        decision: PlannerDecision,
        stepIndex: Int,
        worldState: WorldState,
        taskContext: TaskContext,
        budget: LoopBudget,
        surface: RuntimeSurface,
        runState: inout RunState
    ) async -> LoopTermination {
        let toolResult = executionDriver.execute(
            intent: prepared.intent,
            plannerDecision: decision,
            selectedCandidate: prepared.selectedCandidate
        )
        runState.lastAction = prepared.intent

        if let budgetReason = runState.budgetState.registerExecution(
            intent: prepared.intent,
            budget: budget
        ) {
            runState.diagnostics.recordDecision(
                stepIndex: stepIndex,
                decision: decision,
                success: false,
                failure: .patchApplyFailed,
                notes: decision.notes + ["code budget exceeded"]
            )
            return .finished(
                finalize(
                    reason: budgetReason,
                    finalWorldState: worldState,
                    steps: stepIndex + 1,
                    lastFailure: .patchApplyFailed,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            )
        }

        let actionResult = actionResult(from: toolResult)
        if actionResult.success {
            runState.diagnostics.recordDecision(
                stepIndex: stepIndex,
                decision: decision,
                success: true,
                notes: decision.notes
            )
            projectMemoryCoordinator.recordKnownGoodPattern(
                decision: decision,
                intent: prepared.intent,
                taskContext: taskContext
            )
            projectMemoryCoordinator.recordArchitectureDecision(
                decision: decision,
                taskContext: taskContext
            )
            return .continueRunning
        }

        let afterObservation = observationProvider.observe()
        let afterWorldState = WorldState(
            observation: afterObservation,
            lastAction: prepared.intent,
            repositorySnapshot: repositorySnapshot(for: taskContext),
            stateAbstraction: stateAbstraction
        )
        let failure = FailureAnalyzer.classify(
            intent: prepared.intent,
            result: actionResult,
            before: worldState.observation,
            after: afterObservation,
            selectedCandidate: prepared.selectedCandidate,
            ambiguityScore: prepared.selectedCandidate?.ambiguityScore
        ) ?? .actionFailed

        MemoryUpdater.recordFailure(
            failure: failure,
            state: afterWorldState,
            store: memoryStore
        )
        runState.diagnostics.recordDecision(
            stepIndex: stepIndex,
            decision: decision,
            success: false,
            failure: failure,
            notes: decision.notes
        )

        return await attemptRecovery(
            failure: failure,
            decision: decision,
            recoveryState: afterWorldState,
            finalWorldState: afterWorldState,
            stepIndex: stepIndex,
            taskContext: taskContext,
            budget: budget,
            surface: surface,
            runState: &runState,
            successNote: "bounded recovery succeeded",
            failureNote: "bounded recovery failed"
        )
    }

    private func handlePreparationFailure(
        failure: FailureClass,
        decision: PlannerDecision,
        worldState: WorldState,
        stepIndex: Int,
        taskContext: TaskContext,
        budget: LoopBudget,
        surface: RuntimeSurface,
        runState: inout RunState
    ) async -> LoopTermination {
        runState.diagnostics.recordDecision(
            stepIndex: stepIndex,
            decision: decision,
            success: false,
            failure: failure,
            notes: decision.notes + ["preparation failure"]
        )

        return await attemptRecovery(
            failure: failure,
            decision: decision,
            recoveryState: worldState,
            finalWorldState: worldState,
            stepIndex: stepIndex,
            taskContext: taskContext,
            budget: budget,
            surface: surface,
            runState: &runState,
            successNote: "recovery succeeded after preparation failure",
            failureNote: "recovery failed after preparation failure"
        )
    }

    private func attemptRecovery(
        failure: FailureClass,
        decision: PlannerDecision,
        recoveryState: WorldState,
        finalWorldState: WorldState,
        stepIndex: Int,
        taskContext: TaskContext,
        budget: LoopBudget,
        surface: RuntimeSurface,
        runState: inout RunState,
        successNote: String,
        failureNote: String
    ) async -> LoopTermination {
        guard runState.budgetState.canRecover(under: budget) else {
            return .finished(
                finalize(
                    reason: .unrecoverableFailure,
                    finalWorldState: finalWorldState,
                    steps: stepIndex + 1,
                    lastFailure: failure,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            )
        }

        runState.budgetState.registerRecoveryAttempt()
        let recoveryAttempt = await recoveryEngine.recover(
            failure: failure,
            state: recoveryState,
            memoryStore: memoryStore
        )

        guard let preparation = recoveryAttempt.preparation else {
            memoryStore.recordStrategy(
                StrategyRecord(
                    app: recoveryState.observation.app ?? "unknown",
                    strategy: recoveryAttempt.strategyName ?? "none",
                    success: false
                )
            )
            runState.diagnostics.recordRecovery(
                stepIndex: stepIndex,
                strategyName: recoveryAttempt.strategyName,
                success: false,
                failure: failure,
                notes: [failureNote, recoveryAttempt.message]
            )
            return .finished(
                finalize(
                    reason: .unrecoverableFailure,
                    finalWorldState: finalWorldState,
                    steps: stepIndex + 1,
                    lastFailure: failure,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            )
        }

        return await executeRecoveryPreparation(
            preparation,
            failure: failure,
            originatingDecision: decision,
            recoveryState: recoveryState,
            finalWorldState: finalWorldState,
            stepIndex: stepIndex,
            taskContext: taskContext,
            surface: surface,
            runState: &runState,
            successNote: successNote,
            failureNote: failureNote
        )
    }

    private func executeRecoveryPreparation(
        _ preparation: RecoveryPreparation,
        failure: FailureClass,
        originatingDecision: PlannerDecision,
        recoveryState: WorldState,
        finalWorldState: WorldState,
        stepIndex: Int,
        taskContext: TaskContext,
        surface: RuntimeSurface,
        runState: inout RunState,
        successNote: String,
        failureNote: String
    ) async -> LoopTermination {
        let recoveryDecision = makeRecoveryDecision(
            from: originatingDecision,
            preparation: preparation,
            failure: failure
        )

        let policyDecision = policyEngine.evaluate(
            intent: preparation.resolution.intent,
            context: PolicyEvaluationContext(
                surface: surface,
                toolName: "agent_loop_recovery",
                appName: preparation.resolution.intent.app,
                agentKind: preparation.resolution.intent.agentKind,
                workspaceRoot: preparation.resolution.intent.workspaceRoot,
                workspaceRelativePath: preparation.resolution.intent.workspaceRelativePath,
                commandCategory: preparation.resolution.intent.commandCategory
            )
        )

        if policyDecision.blockedByPolicy || policyDecision.requiresApproval {
            memoryStore.recordStrategy(
                StrategyRecord(
                    app: recoveryState.observation.app ?? "unknown",
                    strategy: preparation.strategyName,
                    success: false
                )
            )
            runState.diagnostics.recordRecovery(
                stepIndex: stepIndex,
                strategyName: preparation.strategyName,
                success: false,
                failure: failure,
                notes: preparation.notes + [failureNote, "recovery blocked by policy"]
            )
            return .finished(
                finalize(
                    reason: .policyBlocked,
                    finalWorldState: finalWorldState,
                    steps: stepIndex + 1,
                    lastFailure: failure,
                    decision: recoveryDecision,
                    taskContext: taskContext,
                    runState: runState
                )
            )
        }

        let toolResult = executionDriver.execute(
            intent: preparation.resolution.intent,
            plannerDecision: recoveryDecision,
            selectedCandidate: preparation.resolution.selectedCandidate
        )
        runState.lastAction = preparation.resolution.intent

        let actionResult = actionResult(from: toolResult)
        memoryStore.recordStrategy(
            StrategyRecord(
                app: recoveryState.observation.app ?? "unknown",
                strategy: preparation.strategyName,
                success: actionResult.success
            )
        )

        if actionResult.success {
            runState.diagnostics.recordRecovery(
                stepIndex: stepIndex,
                strategyName: preparation.strategyName,
                success: true,
                notes: preparation.notes + [successNote]
            )
            return .continueRunning
        }

        let afterObservation = observationProvider.observe()
        let afterWorldState = WorldState(
            observation: afterObservation,
            lastAction: preparation.resolution.intent,
            repositorySnapshot: repositorySnapshot(for: taskContext),
            stateAbstraction: stateAbstraction
        )
        let recoveryFailure = FailureAnalyzer.classify(
            intent: preparation.resolution.intent,
            result: actionResult,
            before: recoveryState.observation,
            after: afterObservation,
            selectedCandidate: preparation.resolution.selectedCandidate,
            ambiguityScore: preparation.resolution.selectedCandidate?.ambiguityScore
        ) ?? failure

        MemoryUpdater.recordFailure(
            failure: recoveryFailure,
            state: afterWorldState,
            store: memoryStore
        )
        runState.diagnostics.recordRecovery(
            stepIndex: stepIndex,
            strategyName: preparation.strategyName,
            success: false,
            failure: recoveryFailure,
            notes: preparation.notes + [failureNote]
        )
        return .finished(
            finalize(
                reason: .unrecoverableFailure,
                finalWorldState: afterWorldState,
                steps: stepIndex + 1,
                lastFailure: recoveryFailure,
                decision: recoveryDecision,
                taskContext: taskContext,
                runState: runState
            )
        )
    }

    private func makeRecoveryDecision(
        from originatingDecision: PlannerDecision,
        preparation: RecoveryPreparation,
        failure: FailureClass
    ) -> PlannerDecision {
        let selectedLabel = preparation.resolution.selectedCandidate?.element.label
        let actionContract = ActionContract.from(
            intent: preparation.resolution.intent,
            method: preparation.resolution.semanticQuery == nil ? "recovery" : "recovery-query",
            selectedElementLabel: selectedLabel,
            plannerFamily: originatingDecision.plannerFamily.rawValue
        )

        return PlannerDecision(
            agentKind: preparation.resolution.intent.agentKind,
            skillName: actionContract.skillName,
            plannerFamily: originatingDecision.plannerFamily,
            stepPhase: originatingDecision.stepPhase,
            actionContract: actionContract,
            source: .recovery,
            workflowID: originatingDecision.workflowID,
            workflowStepID: originatingDecision.workflowStepID,
            semanticQuery: preparation.resolution.semanticQuery,
            projectMemoryRefs: originatingDecision.projectMemoryRefs,
            architectureFindings: originatingDecision.architectureFindings,
            refactorProposalID: originatingDecision.refactorProposalID,
            knowledgeTier: .recovery,
            notes: originatingDecision.notes + preparation.notes,
            recoveryTagged: true,
            recoveryStrategy: preparation.strategyName,
            recoverySource: failure.rawValue
        )
    }

    private func finalize(
        reason: LoopTerminationReason,
        finalWorldState: WorldState?,
        steps: Int,
        lastFailure: FailureClass?,
        decision: PlannerDecision?,
        taskContext: TaskContext,
        runState: RunState
    ) -> LoopOutcome {
        let outcome = LoopOutcome(
            reason: reason,
            finalWorldState: finalWorldState,
            steps: steps,
            recoveries: runState.budgetState.recoveries,
            lastFailure: lastFailure,
            diagnostics: runState.diagnostics
        )

        if reason != .goalAchieved {
            projectMemoryCoordinator.recordOpenProblem(
                outcome: outcome,
                taskContext: taskContext,
                decision: decision
            )
        }

        return outcome
    }

    private func actionResult(from toolResult: ToolResult) -> ActionResult {
        ActionResult.from(dict: toolResult.data?["action_result"] as? [String: Any] ?? [:])
            ?? ActionResult(
                success: toolResult.success,
                verified: toolResult.success,
                message: toolResult.error
            )
    }

    private func captureWorldState(lastAction: ActionIntent?, taskContext: TaskContext) -> WorldState {
        let observation = observationProvider.observe()
        let repositorySnapshot = repositorySnapshot(for: taskContext)
        return WorldState(
            observation: observation,
            lastAction: lastAction,
            repositorySnapshot: repositorySnapshot
        )
    }

    private func prepareAction(
        decision: PlannerDecision,
        state: WorldState,
        taskContext: TaskContext
    ) throws -> SkillResolution {
        if decision.agentKind == .code {
            guard let codeSkill = skillRegistry.getCode(decision.skillName) else {
                throw CodeSkillResolutionError.noRelevantFiles(decision.skillName)
            }
            return try codeSkill.resolve(
                taskContext: taskContext,
                state: state,
                memoryStore: memoryStore
            )
        }

        if decision.actionContract.skillName == "focus" {
            let app = decision.actionContract.targetLabel ?? state.observation.app ?? "unknown"
            let intent = ActionIntent.focus(app: app)
            return SkillResolution(intent: intent)
        }

        if let skill = skillRegistry.get(decision.skillName) {
            let query = decision.semanticQuery ?? ElementQuery(
                text: decision.actionContract.targetLabel,
                role: decision.actionContract.targetRole,
                editable: decision.skillName == "type" || decision.skillName == "fill_form",
                clickable: decision.skillName == "click" || decision.skillName == "read_file",
                visibleOnly: true,
                app: state.observation.app
            )
            return try skill.resolve(
                query: query,
                state: state,
                memoryStore: memoryStore
            )
        }

        let intent = ActionIntent(
            agentKind: decision.agentKind,
            app: state.observation.app ?? decision.actionContract.targetLabel ?? "unknown",
            name: decision.actionContract.skillName,
            action: decision.actionContract.skillName,
            query: decision.actionContract.targetLabel,
            role: decision.actionContract.targetRole,
            workspaceRelativePath: decision.actionContract.workspaceRelativePath
        )
        return SkillResolution(intent: intent, semanticQuery: decision.semanticQuery)
    }

    private func repositorySnapshot(for taskContext: TaskContext) -> RepositorySnapshot? {
        guard taskContext.agentKind == .code || taskContext.agentKind == .mixed,
              let workspaceRoot = taskContext.workspaceRoot
        else {
            return nil
        }
        return repositoryIndexer.index(
            workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        )
    }
}
