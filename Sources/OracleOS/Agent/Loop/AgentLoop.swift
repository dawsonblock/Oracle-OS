import Foundation

@MainActor
public final class AgentLoop {
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
        self.projectMemoryCoordinator = LoopProjectMemoryCoordinator(memoryStore: memoryStore)
        self.experimentCoordinator = LoopExperimentCoordinator(
            experimentManager: experimentManager,
            executionDriver: executionDriver,
            observationProvider: observationProvider,
            stateAbstraction: stateAbstraction,
            recoveryEngine: recoveryEngine,
            memoryStore: memoryStore,
            repositoryIndexer: repositoryIndexer,
            projectMemoryCoordinator: LoopProjectMemoryCoordinator(memoryStore: memoryStore)
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

        var latestWorldState: WorldState?
        var lastAction: ActionIntent?
        var recoveries = 0
        var consecutiveExplorationSteps = 0
        var patchIterations = 0
        var buildAttempts = 0
        var testAttempts = 0
        var diagnostics = LoopDiagnostics.empty

        for step in 0..<budget.maxSteps {
            let worldState = captureWorldState(lastAction: lastAction, taskContext: taskContext)
            latestWorldState = worldState

            if planner.goalReached(state: worldState.planningState) {
                return LoopOutcome(
                    reason: .goalAchieved,
                    finalWorldState: worldState,
                    steps: step,
                    recoveries: recoveries,
                    diagnostics: diagnostics
                )
            }

            guard let decision = planner.nextStep(
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore
            ) else {
                return LoopOutcome(
                    reason: .noViablePlan,
                    finalWorldState: worldState,
                    steps: step,
                    recoveries: recoveries,
                    diagnostics: diagnostics
                )
            }

            if decision.source == .exploration {
                consecutiveExplorationSteps += 1
                if consecutiveExplorationSteps > budget.maxConsecutiveExplorationSteps {
                    return LoopOutcome(
                        reason: .explorationBudgetExceeded,
                        finalWorldState: worldState,
                        steps: step,
                        recoveries: recoveries,
                        diagnostics: diagnostics
                    )
                }
            } else {
                consecutiveExplorationSteps = 0
            }

            if decision.executionMode == .experiment,
               let experimentSpec = decision.experimentSpec
            {
                let experimentOutcome = await experimentCoordinator.handle(
                    decision: decision,
                    experimentSpec: experimentSpec,
                    taskContext: taskContext,
                    worldState: worldState,
                    recoveries: &recoveries,
                    step: step,
                    budget: budget,
                    diagnostics: &diagnostics
                )
                if let experimentOutcome {
                    return experimentOutcome
                }
                continue
            }

            let prepared: SkillResolution
            do {
                prepared = try prepareAction(decision: decision, state: worldState, taskContext: taskContext)
            } catch let error as SkillResolutionError {
                if let outcome = await handlePreparationFailure(
                    failure: error.failureClass,
                    decision: decision,
                    worldState: worldState,
                    recoveries: &recoveries,
                    step: step,
                    budget: budget,
                    diagnostics: &diagnostics
                ) {
                    return outcome
                }
                continue
            } catch let error as CodeSkillResolutionError {
                if let outcome = await handlePreparationFailure(
                    failure: error.failureClass,
                    decision: decision,
                    worldState: worldState,
                    recoveries: &recoveries,
                    step: step,
                    budget: budget,
                    diagnostics: &diagnostics
                ) {
                    return outcome
                }
                continue
            } catch {
                return LoopOutcome(
                    reason: .unrecoverableFailure,
                    finalWorldState: worldState,
                    steps: step + 1,
                    recoveries: recoveries,
                    lastFailure: .actionFailed,
                    diagnostics: diagnostics
                )
            }

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
            if policyDecision.blockedByPolicy || policyDecision.requiresApproval {
                diagnostics.append(
                    LoopStepSummary(
                        stepIndex: step,
                        source: decision.source,
                        skillName: decision.skillName,
                        workflowID: decision.workflowID,
                        experimentID: decision.experimentSpec?.id,
                        success: false,
                        failure: .actionFailed,
                        notes: decision.notes + ["policy precheck blocked execution"]
                    )
                )
                return LoopOutcome(
                    reason: .policyBlocked,
                    finalWorldState: worldState,
                    steps: step,
                    recoveries: recoveries,
                    diagnostics: diagnostics
                )
            }

            let result = executionDriver.execute(
                intent: prepared.intent,
                plannerDecision: decision,
                selectedCandidate: prepared.selectedCandidate
            )
            lastAction = prepared.intent
            incrementCounters(
                intent: prepared.intent,
                patchIterations: &patchIterations,
                buildAttempts: &buildAttempts,
                testAttempts: &testAttempts
            )
            if exceedsCodeBudget(
                patchIterations: patchIterations,
                buildAttempts: buildAttempts,
                testAttempts: testAttempts,
                budget: budget
            ) {
                diagnostics.append(
                    LoopStepSummary(
                        stepIndex: step,
                        source: decision.source,
                        skillName: decision.skillName,
                        workflowID: decision.workflowID,
                        experimentID: decision.experimentSpec?.id,
                        success: false,
                        failure: .patchApplyFailed,
                        notes: decision.notes + ["code budget exceeded"]
                    )
                )
                return LoopOutcome(
                    reason: .lowConfidenceRepeatedFailure,
                    finalWorldState: worldState,
                    steps: step + 1,
                    recoveries: recoveries,
                    diagnostics: diagnostics
                )
            }

            let actionResult = ActionResult.from(dict: result.data?["action_result"] as? [String: Any] ?? [:])
                ?? ActionResult(
                    success: result.success,
                    verified: result.success,
                    message: result.error
                )

            if actionResult.success {
                diagnostics.append(
                    LoopStepSummary(
                        stepIndex: step,
                        source: decision.source,
                        skillName: decision.skillName,
                        workflowID: decision.workflowID,
                        experimentID: decision.experimentSpec?.id,
                        success: true,
                        notes: decision.notes
                    )
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
                continue
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
            diagnostics.append(
                LoopStepSummary(
                    stepIndex: step,
                    source: decision.source,
                    skillName: decision.skillName,
                    workflowID: decision.workflowID,
                    experimentID: decision.experimentSpec?.id,
                    success: false,
                    failure: failure,
                    notes: decision.notes
                )
            )

            if recoveries < budget.maxRecoveries {
                let recoveryAttempt = await recoveryEngine.recover(
                    failure: failure,
                    state: afterWorldState,
                    memoryStore: memoryStore
                )
                recoveries += 1
                memoryStore.recordStrategy(
                    StrategyRecord(
                        app: afterObservation.app ?? "unknown",
                        strategy: recoveryAttempt.strategyName ?? "none",
                        success: recoveryAttempt.result.success
                    )
                )
                if recoveryAttempt.result.success {
                    diagnostics.append(
                        LoopStepSummary(
                            stepIndex: step,
                            source: .recovery,
                            skillName: recoveryAttempt.strategyName ?? "recovery",
                            success: true,
                            recoveryStrategy: recoveryAttempt.strategyName,
                            notes: ["bounded recovery succeeded"]
                        )
                    )
                    continue
                }
            }

            let outcome = LoopOutcome(
                reason: .unrecoverableFailure,
                finalWorldState: worldState,
                steps: step + 1,
                recoveries: recoveries,
                lastFailure: failure,
                diagnostics: diagnostics
            )
            projectMemoryCoordinator.recordOpenProblem(
                outcome: outcome,
                taskContext: taskContext,
                decision: decision
            )
            return outcome
        }

        let outcome = LoopOutcome(
            reason: .maxSteps,
            finalWorldState: latestWorldState,
            steps: budget.maxSteps,
            recoveries: recoveries,
            diagnostics: diagnostics
        )
        projectMemoryCoordinator.recordOpenProblem(
            outcome: outcome,
            taskContext: taskContext,
            decision: nil
        )
        return outcome
    }

    public func run(goal: String, state: WorldState) async {
        let interpretedGoal = planner.interpretGoal(goal)
        planner.setGoal(interpretedGoal)
        _ = planner.nextStep(worldState: state, graphStore: graphStore)
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
        return repositoryIndexer.index(workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
    }

    private func handlePreparationFailure(
        failure: FailureClass,
        decision: PlannerDecision,
        worldState: WorldState,
        recoveries: inout Int,
        step: Int,
        budget: LoopBudget,
        diagnostics: inout LoopDiagnostics
    ) async -> LoopOutcome? {
        diagnostics.append(
            LoopStepSummary(
                stepIndex: step,
                source: decision.source,
                skillName: decision.skillName,
                workflowID: decision.workflowID,
                experimentID: decision.experimentSpec?.id,
                success: false,
                failure: failure,
                notes: decision.notes + ["preparation failure"]
            )
        )
        if recoveries < budget.maxRecoveries {
            let recoveryAttempt = await recoveryEngine.recover(
                failure: failure,
                state: worldState,
                memoryStore: memoryStore
            )
            recoveries += 1
            memoryStore.recordStrategy(
                StrategyRecord(
                    app: worldState.observation.app ?? "unknown",
                    strategy: recoveryAttempt.strategyName ?? "none",
                    success: recoveryAttempt.result.success
                )
            )
            if recoveryAttempt.result.success {
                diagnostics.append(
                    LoopStepSummary(
                        stepIndex: step,
                        source: .recovery,
                        skillName: recoveryAttempt.strategyName ?? "recovery",
                        success: true,
                        recoveryStrategy: recoveryAttempt.strategyName,
                        notes: ["recovery succeeded after preparation failure"]
                    )
                )
                return nil
            }
        }

        return LoopOutcome(
            reason: .unrecoverableFailure,
            finalWorldState: worldState,
            steps: step + 1,
            recoveries: recoveries,
            lastFailure: failure,
            diagnostics: diagnostics
        )
    }

    private func incrementCounters(
        intent: ActionIntent,
        patchIterations: inout Int,
        buildAttempts: inout Int,
        testAttempts: inout Int
    ) {
        switch intent.commandCategory {
        case CodeCommandCategory.generatePatch.rawValue, CodeCommandCategory.editFile.rawValue, CodeCommandCategory.writeFile.rawValue:
            patchIterations += 1
        case CodeCommandCategory.build.rawValue:
            buildAttempts += 1
        case CodeCommandCategory.test.rawValue:
            testAttempts += 1
        default:
            break
        }
    }

    private func exceedsCodeBudget(
        patchIterations: Int,
        buildAttempts: Int,
        testAttempts: Int,
        budget: LoopBudget
    ) -> Bool {
        patchIterations > budget.maxPatchIterations
            || buildAttempts > budget.maxBuildAttempts
            || testAttempts > budget.maxTestAttempts
    }

}
