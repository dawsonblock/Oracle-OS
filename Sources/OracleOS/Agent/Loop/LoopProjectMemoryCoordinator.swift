import Foundation

public struct LoopProjectMemoryCoordinator: @unchecked Sendable {
    private let memoryStore: AppMemoryStore

    public init(memoryStore: AppMemoryStore) {
        self.memoryStore = memoryStore
    }

    public func recordOpenProblem(
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
                knowledgeClass: .reusable,
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

    public func recordArchitectureDecision(
        decision: PlannerDecision,
        taskContext: TaskContext
    ) {
        let majorFindings = decision.architectureFindings.filter {
            $0.severity == .critical || $0.riskScore >= 0.5
        }
        guard !majorFindings.isEmpty,
              let refactorProposalID = decision.refactorProposalID,
              taskContext.agentKind == .code || taskContext.agentKind == .mixed
        else {
            return
        }

        do {
            let store = try projectMemoryStore(for: taskContext)
            _ = try store.writeArchitectureDecisionDraft(
                title: "Architecture review for \(taskContext.goal.description)",
                summary: "High-impact change surfaced \(majorFindings.count) major architecture finding(s).",
                knowledgeClass: .reusable,
                affectedModules: Array(Set(majorFindings.flatMap(\.affectedModules))).sorted(),
                evidenceRefs: decision.projectMemoryRefs.map(\.path),
                sourceTraceIDs: [],
                body: """
                Refactor proposal id: \(refactorProposalID)

                Findings:
                \(majorFindings.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n"))
                """
            )
        } catch {
            return
        }
    }

    public func recordKnownGoodPattern(
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
                knowledgeClass: .reusable,
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

    public func recordRejectedApproach(
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
                knowledgeClass: .reusable,
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
