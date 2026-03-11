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
    private let experimentManager: ExperimentManager

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
        self.experimentManager = experimentManager
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

        for step in 0..<budget.maxSteps {
            let worldState = captureWorldState(lastAction: lastAction, taskContext: taskContext)
            latestWorldState = worldState

            if planner.goalReached(state: worldState.planningState) {
                return LoopOutcome(
                    reason: .goalAchieved,
                    finalWorldState: worldState,
                    steps: step,
                    recoveries: recoveries
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
                    recoveries: recoveries
                )
            }

            if decision.source == .exploration {
                consecutiveExplorationSteps += 1
                if consecutiveExplorationSteps > budget.maxConsecutiveExplorationSteps {
                    return LoopOutcome(
                        reason: .explorationBudgetExceeded,
                        finalWorldState: worldState,
                        steps: step,
                        recoveries: recoveries
                    )
                }
            } else {
                consecutiveExplorationSteps = 0
            }

            if decision.executionMode == .experiment,
               let experimentSpec = decision.experimentSpec
            {
                let experimentOutcome = await handleExperimentDecision(
                    decision: decision,
                    experimentSpec: experimentSpec,
                    taskContext: taskContext,
                    worldState: worldState,
                    recoveries: &recoveries,
                    step: step,
                    budget: budget
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
                    budget: budget
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
                    budget: budget
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
                    lastFailure: .actionFailed
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
                return LoopOutcome(
                    reason: .policyBlocked,
                    finalWorldState: worldState,
                    steps: step,
                    recoveries: recoveries
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
                return LoopOutcome(
                    reason: .lowConfidenceRepeatedFailure,
                    finalWorldState: worldState,
                    steps: step + 1,
                    recoveries: recoveries
                )
            }

            let actionResult = ActionResult.from(dict: result.data?["action_result"] as? [String: Any] ?? [:])
                ?? ActionResult(
                    success: result.success,
                    verified: result.success,
                    message: result.error
                )

            if actionResult.success {
                maybeRecordKnownGoodPattern(
                    decision: decision,
                    intent: prepared.intent,
                    taskContext: taskContext
                )
                maybeRecordArchitectureDecision(
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
                    continue
                }
            }

            let outcome = LoopOutcome(
                reason: .unrecoverableFailure,
                finalWorldState: worldState,
                steps: step + 1,
                recoveries: recoveries,
                lastFailure: failure
            )
            recordOpenProblemIfNeeded(outcome: outcome, taskContext: taskContext, decision: decision)
            return outcome
        }

        let outcome = LoopOutcome(
            reason: .maxSteps,
            finalWorldState: latestWorldState,
            steps: budget.maxSteps,
            recoveries: recoveries
        )
        recordOpenProblemIfNeeded(outcome: outcome, taskContext: taskContext, decision: nil)
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

        switch decision.actionContract.skillName {
        case "click":
            guard let clickSkill = skillRegistry.get("click") as? ClickSkill else {
                throw SkillResolutionError.noCandidate("click skill unavailable")
            }
            let query = decision.semanticQuery ?? ElementQuery(
                text: decision.actionContract.targetLabel,
                role: decision.actionContract.targetRole,
                editable: false,
                clickable: true,
                visibleOnly: true,
                app: state.observation.app
            )
            return try clickSkill.resolve(
                query: query,
                state: state,
                memoryStore: memoryStore
            )
        case "focus":
            let app = decision.actionContract.targetLabel ?? state.observation.app ?? "unknown"
            let intent = ActionIntent.focus(app: app)
            return SkillResolution(intent: intent)
        default:
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
        budget: LoopBudget
    ) async -> LoopOutcome? {
        graphStore.recordFailure(
            state: worldState.planningState,
            actionContract: decision.actionContract,
            failure: failure,
            ambiguityScore: failure == .elementAmbiguous || failure == .ambiguousEditTarget ? 1 : 0,
            recoveryTagged: decision.recoveryTagged
        )
        _ = graphStore.promoteEligibleEdges()
        _ = graphStore.pruneOrDemoteEdges()
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
                return nil
            }
        }

        return LoopOutcome(
            reason: .unrecoverableFailure,
            finalWorldState: worldState,
            steps: step + 1,
            recoveries: recoveries,
            lastFailure: failure
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

    private func handleExperimentDecision(
        decision: PlannerDecision,
        experimentSpec: ExperimentSpec,
        taskContext: TaskContext,
        worldState: WorldState,
        recoveries: inout Int,
        step: Int,
        budget: LoopBudget
    ) async -> LoopOutcome? {
        do {
            let results = try await experimentManager.run(
                spec: experimentSpec,
                architectureRiskScore: decision.architectureFindings.map(\.riskScore).max() ?? 0
            )
            guard let selected = experimentManager.replaySelected(from: results) else {
                writeRejectedApproachDraft(
                    title: "Experiment fanout produced no viable winner",
                    taskContext: taskContext,
                    decision: decision,
                    body: results.map { "\($0.candidate.title): \($0.commandResults.map(\.succeeded).allSatisfy { $0 })" }.joined(separator: "\n")
                )
                return LoopOutcome(
                    reason: .lowConfidenceRepeatedFailure,
                    finalWorldState: worldState,
                    steps: step + 1,
                    recoveries: recoveries,
                    lastFailure: .patchApplyFailed
                )
            }

            let replayCommand = CommandSpec(
                category: .generatePatch,
                executable: "/usr/bin/env",
                arguments: [],
                workspaceRoot: experimentSpec.workspaceRoot,
                workspaceRelativePath: selected.workspaceRelativePath,
                summary: "replay experiment candidate \(selected.title)"
            )
            let replayIntent = ActionIntent.code(
                name: "Replay experiment candidate",
                command: replayCommand,
                workspaceRelativePath: selected.workspaceRelativePath,
                text: selected.content
            )
            let replayContract = ActionContract(
                id: [
                    "code",
                    "experiment-replay",
                    selected.workspaceRelativePath,
                    experimentSpec.id,
                    selected.id,
                ].joined(separator: "|"),
                agentKind: .code,
                skillName: "generate_patch",
                targetRole: nil,
                targetLabel: selected.title,
                locatorStrategy: "experiment-replay",
                workspaceRelativePath: selected.workspaceRelativePath,
                commandCategory: CodeCommandCategory.generatePatch.rawValue,
                plannerFamily: PlannerFamily.code.rawValue
            )
            let selectedResult = results.first(where: { $0.candidate.id == selected.id })
            let replayDecision = PlannerDecision(
                agentKind: .code,
                skillName: "generate_patch",
                plannerFamily: .code,
                stepPhase: .engineering,
                executionMode: .direct,
                actionContract: replayContract,
                source: .exploration,
                projectMemoryRefs: decision.projectMemoryRefs,
                architectureFindings: decision.architectureFindings,
                refactorProposalID: decision.refactorProposalID,
                experimentSpec: experimentSpec,
                experimentCandidateID: selected.id,
                experimentSandboxPath: selectedResult?.sandboxPath,
                selectedExperimentCandidate: true,
                experimentOutcome: selectedResult?.succeeded == true ? "selected-replay" : "selected-with-failures",
                knowledgeTier: .candidate,
                notes: decision.notes + ["replaying selected experiment candidate"]
            )

            let result = executionDriver.execute(
                intent: replayIntent,
                plannerDecision: replayDecision,
                selectedCandidate: nil
            )

            if result.success {
                maybeRecordArchitectureDecision(
                    decision: replayDecision,
                    taskContext: taskContext
                )
                return nil
            }

            if recoveries < budget.maxRecoveries {
                let afterObservation = observationProvider.observe()
                let afterWorldState = WorldState(
                    observation: afterObservation,
                    lastAction: replayIntent,
                    repositorySnapshot: repositorySnapshot(for: taskContext),
                    stateAbstraction: stateAbstraction
                )
                let recoveryAttempt = await recoveryEngine.recover(
                    failure: .patchApplyFailed,
                    state: afterWorldState,
                    memoryStore: memoryStore
                )
                recoveries += 1
                if recoveryAttempt.result.success {
                    return nil
                }
            }

            return LoopOutcome(
                reason: .lowConfidenceRepeatedFailure,
                finalWorldState: worldState,
                steps: step + 1,
                recoveries: recoveries,
                lastFailure: .patchApplyFailed
            )
        } catch {
            writeRejectedApproachDraft(
                title: "Experiment execution failed",
                taskContext: taskContext,
                decision: decision,
                body: error.localizedDescription
            )
            return LoopOutcome(
                reason: .lowConfidenceRepeatedFailure,
                finalWorldState: worldState,
                steps: step + 1,
                recoveries: recoveries,
                lastFailure: .patchApplyFailed
            )
        }
    }

    private func recordOpenProblemIfNeeded(
        outcome: LoopOutcome,
        taskContext: TaskContext,
        decision: PlannerDecision?
    ) {
        guard taskContext.agentKind == .code || taskContext.agentKind == .mixed else {
            return
        }
        guard outcome.reason != .goalAchieved else {
            return
        }
        do {
            let store = try projectMemoryStore(for: taskContext)
            _ = try store.writeOpenProblemDraft(
                title: taskContext.goal.description,
                summary: "Loop ended with \(outcome.reason.rawValue)",
                affectedModules: decision?.architectureFindings.flatMap(\.affectedModules) ?? [],
                evidenceRefs: decision?.projectMemoryRefs.map(\.path) ?? [],
                sourceTraceIDs: [],
                body: """
                Reason: \(outcome.reason.rawValue)
                Last failure: \(outcome.lastFailure?.rawValue ?? "none")
                Steps: \(outcome.steps)
                Recoveries: \(outcome.recoveries)
                """
            )
        } catch {
            return
        }
    }

    private func maybeRecordArchitectureDecision(
        decision: PlannerDecision,
        taskContext: TaskContext
    ) {
        guard !decision.architectureFindings.isEmpty,
              let refactorProposalID = decision.refactorProposalID,
              taskContext.agentKind == .code || taskContext.agentKind == .mixed
        else {
            return
        }

        do {
            let store = try projectMemoryStore(for: taskContext)
            _ = try store.writeArchitectureDecisionDraft(
                title: "Architecture review for \(taskContext.goal.description)",
                summary: "High-impact change touched \(decision.architectureFindings.flatMap(\.affectedModules).count) module references",
                affectedModules: Array(Set(decision.architectureFindings.flatMap(\.affectedModules))).sorted(),
                evidenceRefs: decision.projectMemoryRefs.map(\.path),
                sourceTraceIDs: [],
                body: """
                Refactor proposal id: \(refactorProposalID)

                Findings:
                \(decision.architectureFindings.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n"))
                """
            )
        } catch {
            return
        }
    }

    private func maybeRecordKnownGoodPattern(
        decision: PlannerDecision,
        intent: ActionIntent,
        taskContext: TaskContext
    ) {
        guard intent.agentKind == .code,
              let workspaceRoot = taskContext.workspaceRoot,
              let commandCategory = intent.commandCategory,
              memoryStore.commandBias(category: commandCategory, workspaceRoot: workspaceRoot) >= 0.1
        else {
            return
        }

        do {
            let store = try projectMemoryStore(for: taskContext)
            _ = try store.writeKnownGoodPatternDraft(
                title: "Reliable \(commandCategory) pattern",
                summary: "Command \(commandCategory) has repeated successful verified reuse in this workspace.",
                affectedModules: decision.architectureFindings.flatMap(\.affectedModules),
                evidenceRefs: decision.projectMemoryRefs.map(\.path),
                sourceTraceIDs: [],
                body: """
                Command category: \(commandCategory)
                Workspace path: \(intent.workspaceRelativePath ?? "workspace-root")
                """
            )
        } catch {
            return
        }
    }

    private func writeRejectedApproachDraft(
        title: String,
        taskContext: TaskContext,
        decision: PlannerDecision,
        body: String
    ) {
        guard taskContext.agentKind == .code || taskContext.agentKind == .mixed else {
            return
        }
        do {
            let store = try projectMemoryStore(for: taskContext)
            _ = try store.writeRejectedApproachDraft(
                title: title,
                summary: "Parallel experiment candidates did not produce a safe winner",
                affectedModules: Array(Set(decision.architectureFindings.flatMap(\.affectedModules))).sorted(),
                evidenceRefs: decision.projectMemoryRefs.map(\.path),
                sourceTraceIDs: [],
                body: body
            )
        } catch {
            return
        }
    }

    private func projectMemoryStore(for taskContext: TaskContext) throws -> ProjectMemoryStore {
        guard let workspaceRoot = taskContext.workspaceRoot else {
            throw NSError(domain: "AgentLoop", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing workspace root"])
        }
        return try ProjectMemoryStore(projectRootURL: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
    }
}
