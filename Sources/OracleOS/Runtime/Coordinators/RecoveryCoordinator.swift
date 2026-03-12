import Foundation

@MainActor
public final class RecoveryCoordinator {
    private let observationProvider: any ObservationProvider
    private let executionDriver: any AgentExecutionDriver
    private let stateAbstraction: StateAbstraction
    private let recoveryEngine: RecoveryEngine
    private let policyEngine: PolicyEngine
    private let learningCoordinator: LearningCoordinator
    private let repositoryIndexer: RepositoryIndexer
    private let automationHost: AutomationHost
    private let browserPageStateBuilder: BrowserPageStateBuilder

    public init(
        observationProvider: any ObservationProvider,
        executionDriver: any AgentExecutionDriver,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        recoveryEngine: RecoveryEngine = RecoveryEngine(),
        policyEngine: PolicyEngine = PolicyEngine(),
        learningCoordinator: LearningCoordinator,
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        automationHost: AutomationHost = .live(),
        browserPageStateBuilder: BrowserPageStateBuilder = BrowserPageStateBuilder()
    ) {
        self.observationProvider = observationProvider
        self.executionDriver = executionDriver
        self.stateAbstraction = stateAbstraction
        self.recoveryEngine = recoveryEngine
        self.policyEngine = policyEngine
        self.learningCoordinator = learningCoordinator
        self.repositoryIndexer = repositoryIndexer
        self.automationHost = automationHost
        self.browserPageStateBuilder = browserPageStateBuilder
    }

    public func recover(
        from failure: FailureClass,
        decision: PlannerDecision,
        stateBundle: LoopStateBundle,
        budget: LoopBudget,
        budgetState: inout LoopBudgetState,
        diagnostics: inout LoopDiagnostics,
        stepIndex: Int,
        failureNote: String,
        successNote: String
    ) async -> LoopTermination {
        guard budgetState.canRecover(under: budget) else {
            diagnostics.recordRecovery(
                stepIndex: stepIndex,
                strategyName: nil,
                success: false,
                failure: failure,
                notes: ["recovery budget exhausted"]
            )
            return .finished(
                LoopOutcome(
                    reason: .unrecoverableFailure,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex + 1,
                    recoveries: budgetState.recoveries,
                    lastFailure: failure,
                    diagnostics: diagnostics
                )
            )
        }

        budgetState.registerRecoveryAttempt()
        let recoveryAttempt = await recoveryEngine.recover(
            failure: failure,
            state: stateBundle.worldState,
            memoryStore: learningCoordinator.appMemoryStore
        )

        guard let preparation = recoveryAttempt.preparation else {
            learningCoordinator.recordStrategy(
                app: stateBundle.observation.app ?? "unknown",
                strategy: recoveryAttempt.strategyName ?? "none",
                success: false
            )
            diagnostics.recordRecovery(
                stepIndex: stepIndex,
                strategyName: recoveryAttempt.strategyName,
                success: false,
                failure: failure,
                notes: [failureNote, recoveryAttempt.message]
            )
            return .finished(
                LoopOutcome(
                    reason: .unrecoverableFailure,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex + 1,
                    recoveries: budgetState.recoveries,
                    lastFailure: failure,
                    diagnostics: diagnostics
                )
            )
        }

        let recoveryDecision = makeRecoveryDecision(
            from: decision,
            preparation: preparation,
            failure: failure
        )
        let policyDecision = policyEngine.evaluate(
            intent: preparation.resolution.intent,
            context: PolicyEvaluationContext(
                surface: .recipe,
                toolName: "agent_loop_recovery",
                appName: preparation.resolution.intent.app,
                agentKind: preparation.resolution.intent.agentKind,
                workspaceRoot: preparation.resolution.intent.workspaceRoot,
                workspaceRelativePath: preparation.resolution.intent.workspaceRelativePath,
                commandCategory: preparation.resolution.intent.commandCategory
            )
        )

        if policyDecision.blockedByPolicy || policyDecision.requiresApproval {
            learningCoordinator.recordStrategy(
                app: stateBundle.observation.app ?? "unknown",
                strategy: preparation.strategyName,
                success: false
            )
            diagnostics.recordPolicy(
                stepIndex: stepIndex,
                outcome: .blocked,
                notes: ["recovery blocked by policy"]
            )
            diagnostics.recordRecovery(
                stepIndex: stepIndex,
                strategyName: preparation.strategyName,
                success: false,
                failure: failure,
                notes: preparation.notes + [failureNote, "recovery blocked by policy"]
            )
            let reason: LoopTerminationReason = policyDecision.requiresApproval ? .approvalTimeout : .policyBlocked
            return .finished(
                LoopOutcome(
                    reason: reason,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex + 1,
                    recoveries: budgetState.recoveries,
                    lastFailure: failure,
                    diagnostics: diagnostics
                )
            )
        }

        diagnostics.recordPolicy(stepIndex: stepIndex, outcome: .allowed)
        let toolResult = executionDriver.execute(
            intent: preparation.resolution.intent,
            plannerDecision: recoveryDecision,
            selectedCandidate: preparation.resolution.selectedCandidate
        )
        let actionResult = ActionResult.from(dict: toolResult.data?["action_result"] as? [String: Any] ?? [:])
            ?? ActionResult(success: toolResult.success, verified: toolResult.success, message: toolResult.error)
        learningCoordinator.recordStrategy(
            app: stateBundle.observation.app ?? "unknown",
            strategy: preparation.strategyName,
            success: actionResult.success
        )

        if actionResult.success {
            diagnostics.recordRecovery(
                stepIndex: stepIndex,
                strategyName: preparation.strategyName,
                success: true,
                notes: preparation.notes + [successNote]
            )
            return .continueRunning
        }

        let afterStateBundle = refreshedStateBundle(from: stateBundle, lastAction: preparation.resolution.intent)
        let recoveryFailure = FailureAnalyzer.classify(
            intent: preparation.resolution.intent,
            result: actionResult,
            before: stateBundle.observation,
            after: afterStateBundle.observation,
            selectedCandidate: preparation.resolution.selectedCandidate,
            ambiguityScore: preparation.resolution.selectedCandidate?.ambiguityScore
        ) ?? failure

        learningCoordinator.recordFailure(
            failure: recoveryFailure,
            stateBundle: afterStateBundle
        )
        diagnostics.recordRecovery(
            stepIndex: stepIndex,
            strategyName: preparation.strategyName,
            success: false,
            failure: recoveryFailure,
            notes: preparation.notes + [failureNote]
        )
        return .finished(
            LoopOutcome(
                reason: .unrecoverableFailure,
                finalWorldState: afterStateBundle.worldState,
                steps: stepIndex + 1,
                recoveries: budgetState.recoveries,
                lastFailure: recoveryFailure,
                diagnostics: diagnostics
            )
        )
    }

    private func refreshedStateBundle(from stateBundle: LoopStateBundle, lastAction: ActionIntent?) -> LoopStateBundle {
        let observation = observationProvider.observe()
        let repositorySnapshot = repositorySnapshot(for: stateBundle.taskContext)
        let worldState = WorldState(
            observation: observation,
            lastAction: lastAction,
            repositorySnapshot: repositorySnapshot,
            stateAbstraction: stateAbstraction
        )
        return LoopStateBundle(
            taskContext: stateBundle.taskContext,
            observation: observation,
            worldState: worldState,
            repositorySnapshot: repositorySnapshot,
            hostSnapshot: automationHost.snapshots.captureSnapshot(appName: observation.app),
            browserSession: browserPageStateBuilder.build(from: observation),
            memoryContext: MemoryQueryContext(taskContext: stateBundle.taskContext, worldState: worldState)
        )
    }

    private func repositorySnapshot(for taskContext: TaskContext) -> RepositorySnapshot? {
        guard taskContext.agentKind == .code || taskContext.agentKind == .mixed,
              let workspaceRoot = taskContext.workspaceRoot
        else {
            return nil
        }
        return repositoryIndexer.indexIfNeeded(workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
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
            fallbackReason: originatingDecision.fallbackReason,
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
}
