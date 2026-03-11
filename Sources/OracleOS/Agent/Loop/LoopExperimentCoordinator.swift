import Foundation

@MainActor
public final class LoopExperimentCoordinator {
    private let experimentManager: ExperimentManager
    private let executionDriver: any AgentExecutionDriver
    private let observationProvider: any ObservationProvider
    private let stateAbstraction: StateAbstraction
    private let recoveryEngine: RecoveryEngine
    private let memoryStore: AppMemoryStore
    private let projectMemoryCoordinator: LoopProjectMemoryCoordinator
    private let repositoryIndexer: RepositoryIndexer

    public init(
        experimentManager: ExperimentManager,
        executionDriver: any AgentExecutionDriver,
        observationProvider: any ObservationProvider,
        stateAbstraction: StateAbstraction,
        recoveryEngine: RecoveryEngine,
        memoryStore: AppMemoryStore,
        repositoryIndexer: RepositoryIndexer,
        projectMemoryCoordinator: LoopProjectMemoryCoordinator
    ) {
        self.experimentManager = experimentManager
        self.executionDriver = executionDriver
        self.observationProvider = observationProvider
        self.stateAbstraction = stateAbstraction
        self.recoveryEngine = recoveryEngine
        self.memoryStore = memoryStore
        self.repositoryIndexer = repositoryIndexer
        self.projectMemoryCoordinator = projectMemoryCoordinator
    }

    public func handle(
        decision: PlannerDecision,
        experimentSpec: ExperimentSpec,
        taskContext: TaskContext,
        worldState: WorldState,
        recoveries: inout Int,
        step: Int,
        budget: LoopBudget,
        diagnostics: inout LoopDiagnostics
    ) async -> LoopOutcome? {
        do {
            let results = try await experimentManager.run(
                spec: experimentSpec,
                architectureRiskScore: decision.architectureFindings.map(\.riskScore).max() ?? 0
            )
            guard let selected = experimentManager.replaySelected(from: results) else {
                projectMemoryCoordinator.recordRejectedApproach(
                    title: "Experiment fanout produced no viable winner",
                    taskContext: taskContext,
                    decision: decision,
                    body: results.map { "\($0.candidate.title): \($0.commandResults.map(\.succeeded).allSatisfy { $0 })" }.joined(separator: "\n")
                )
                diagnostics.append(
                    LoopStepSummary(
                        stepIndex: step,
                        source: decision.source,
                        skillName: decision.skillName,
                        experimentID: experimentSpec.id,
                        success: false,
                        failure: .patchApplyFailed,
                        notes: decision.notes + ["no experiment candidate passed ranking"]
                    )
                )
                return LoopOutcome(
                    reason: .lowConfidenceRepeatedFailure,
                    finalWorldState: worldState,
                    steps: step + 1,
                    recoveries: recoveries,
                    lastFailure: .patchApplyFailed,
                    diagnostics: diagnostics
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
            let actionResult = ActionResult.from(dict: result.data?["action_result"] as? [String: Any] ?? [:])
                ?? ActionResult(success: result.success, verified: result.success, message: result.error)

            diagnostics.append(
                LoopStepSummary(
                    stepIndex: step,
                    source: replayDecision.source,
                    skillName: replayDecision.skillName,
                    experimentID: experimentSpec.id,
                    success: actionResult.success,
                    failure: actionResult.failureClass.flatMap(FailureClass.init(rawValue:)),
                    notes: replayDecision.notes
                )
            )

            if actionResult.success {
                projectMemoryCoordinator.recordArchitectureDecision(
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
                    diagnostics.append(
                        LoopStepSummary(
                            stepIndex: step,
                            source: .recovery,
                            skillName: recoveryAttempt.strategyName ?? "recovery",
                            experimentID: experimentSpec.id,
                            success: true,
                            recoveryStrategy: recoveryAttempt.strategyName,
                            notes: ["experiment replay recovery succeeded"]
                        )
                    )
                    return nil
                }
            }

            return LoopOutcome(
                reason: .lowConfidenceRepeatedFailure,
                finalWorldState: worldState,
                steps: step + 1,
                recoveries: recoveries,
                lastFailure: .patchApplyFailed,
                diagnostics: diagnostics
            )
        } catch {
            projectMemoryCoordinator.recordRejectedApproach(
                title: "Experiment execution failed",
                taskContext: taskContext,
                decision: decision,
                body: error.localizedDescription
            )
            diagnostics.append(
                LoopStepSummary(
                    stepIndex: step,
                    source: decision.source,
                    skillName: decision.skillName,
                    experimentID: experimentSpec.id,
                    success: false,
                    failure: .patchApplyFailed,
                    notes: decision.notes + [error.localizedDescription]
                )
            )
            return LoopOutcome(
                reason: .lowConfidenceRepeatedFailure,
                finalWorldState: worldState,
                steps: step + 1,
                recoveries: recoveries,
                lastFailure: .patchApplyFailed,
                diagnostics: diagnostics
            )
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
}
