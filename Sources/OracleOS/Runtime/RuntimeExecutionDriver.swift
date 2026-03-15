import Foundation

@MainActor
public final class RuntimeExecutionDriver: AgentExecutionDriver {
    private let runtime: RuntimeOrchestrator
    private let surface: RuntimeSurface
    private let rawActionExecutor: @MainActor (ActionIntent) -> ToolResult

    public init(
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .recipe,
        rawActionExecutor: @escaping @MainActor (ActionIntent) -> ToolResult
    ) {
        self.runtime = runtime
        self.surface = surface
        self.rawActionExecutor = rawActionExecutor
    }

    public func execute(
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult {
        runtime.performAction(
            surface: surface,
            taskID: nil,
            toolName: "agent_loop",
            intent: intent,
            selectedElementID: selectedCandidate?.element.id,
            selectedElementLabel: selectedCandidate?.element.label,
            candidateScore: selectedCandidate?.score,
            candidateReasons: selectedCandidate?.reasons ?? [],
            candidateAmbiguityScore: selectedCandidate?.ambiguityScore,
            plannerSource: plannerDecision.source.rawValue,
            plannerFamily: plannerDecision.plannerFamily.rawValue,
            pathEdgeIDs: plannerDecision.pathEdgeIDs,
            currentEdgeID: plannerDecision.currentEdgeID,
            recoveryTagged: plannerDecision.recoveryTagged,
            recoveryStrategy: plannerDecision.recoveryStrategy,
            recoverySource: plannerDecision.recoverySource,
            projectMemoryRefs: plannerDecision.projectMemoryRefs.map(\.path),
            experimentID: plannerDecision.experimentSpec?.id,
            candidateID: plannerDecision.experimentCandidateID,
            sandboxPath: plannerDecision.experimentSandboxPath,
            selectedCandidate: plannerDecision.selectedExperimentCandidate,
            experimentOutcome: plannerDecision.experimentOutcome ?? (plannerDecision.executionMode == .experiment ? "requested" : nil),
            architectureFindings: plannerDecision.architectureFindings.map(\.title),
            refactorProposalID: plannerDecision.refactorProposalID,
            knowledgeTier: plannerDecision.knowledgeTier
        ) {
            if intent.agentKind == .code {
                CodeActionGateway(context: runtime.context).execute(intent)
            } else {
                rawActionExecutor(intent)
            }
        }
    }
}
