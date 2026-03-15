import Foundation

/// The top-level runtime that orchestrates every environment-mutating action.
///
/// Required runtime sequence:
///
///     planner proposes → policy authorizes → executor acts → verifier judges
///     → runtime commits → trace records → recovery reacts
///
/// No component may skip a step. The executor is the **sole authority** for
/// environment mutations; the planner and reasoning layers are read-only.
@MainActor
public final class RuntimeOrchestrator {
    public let context: RuntimeContext

    public init(context: RuntimeContext) {
        self.context = context
    }

    public func performAction(
        surface: RuntimeSurface,
        taskID: String? = nil,
        toolName: String? = nil,
        approvalRequestID: String? = nil,
        intent: ActionIntent,
        selectedElementID: String? = nil,
        selectedElementLabel: String? = nil,
        candidateScore: Double? = nil,
        candidateReasons: [String] = [],
        candidateAmbiguityScore: Double? = nil,
        plannerSource: String? = nil,
        plannerFamily: String? = nil,
        pathEdgeIDs: [String]? = nil,
        currentEdgeID: String? = nil,
        recoveryTagged: Bool = false,
        recoveryStrategy: String? = nil,
        recoverySource: String? = nil,
        projectMemoryRefs: [String] = [],
        experimentID: String? = nil,
        candidateID: String? = nil,
        sandboxPath: String? = nil,
        selectedCandidate: Bool? = nil,
        experimentOutcome: String? = nil,
        architectureFindings: [String] = [],
        refactorProposalID: String? = nil,
        knowledgeTier: KnowledgeTier? = nil,
        execute: () -> ToolResult
    ) -> ToolResult {
        let appName = resolvedAppName(for: intent)
        let policyContext = PolicyEvaluationContext(
            surface: surface,
            toolName: toolName,
            appName: appName,
            agentKind: intent.agentKind,
            workspaceRoot: intent.workspaceRoot,
            workspaceRelativePath: intent.workspaceRelativePath,
            commandCategory: intent.commandCategory
        )
        let policyDecision = context.policyEngine.evaluate(intent: intent, context: policyContext)
        let fingerprint = PolicyRules.actionFingerprint(intent: intent, toolName: toolName)

        if policyDecision.requiresApproval {
            if let approvalRequestID,
               let receipt = context.approvalStore.consumeApprovedReceipt(
                   requestID: approvalRequestID,
                   actionFingerprint: fingerprint
               )
            {
                return executeVerified(
                    surface: surface,
                    taskID: taskID,
                    toolName: toolName,
                    intent: intent,
                    selectedElementID: selectedElementID,
                    selectedElementLabel: selectedElementLabel,
                    candidateScore: candidateScore,
                    candidateReasons: candidateReasons,
                    candidateAmbiguityScore: candidateAmbiguityScore,
                    policyDecision: policyDecision,
                    approvalRequestID: approvalRequestID,
                    approvalOutcome: receipt.consumed ? "approved" : "pending",
                    plannerSource: plannerSource,
                    plannerFamily: plannerFamily,
                    pathEdgeIDs: pathEdgeIDs,
                    currentEdgeID: currentEdgeID,
                    recoveryTagged: recoveryTagged,
                    recoveryStrategy: recoveryStrategy,
                    recoverySource: recoverySource,
                    projectMemoryRefs: projectMemoryRefs,
                    experimentID: experimentID,
                    candidateID: candidateID,
                    sandboxPath: sandboxPath,
                    selectedCandidate: selectedCandidate,
                    experimentOutcome: experimentOutcome,
                    architectureFindings: architectureFindings,
                    refactorProposalID: refactorProposalID,
                    knowledgeTier: knowledgeTier,
                    execute: execute
                )
            }

            guard context.approvalStore.controllerConnected() else {
                let deniedDecision = policyDecision.withReason("Approval unavailable: controller is not connected")
                return blockedResult(
                    surface: surface,
                    taskID: taskID,
                    toolName: toolName,
                    intent: intent,
                    policyDecision: deniedDecision,
                    approvalRequestID: nil,
                    approvalStatus: "unavailable",
                    message: deniedDecision.reason ?? "Approval unavailable"
                )
            }

            let request = ApprovalRequest(
                surface: surface,
                toolName: toolName,
                appName: appName,
                displayTitle: intent.name,
                reason: policyDecision.reason ?? "Action requires approval",
                riskLevel: policyDecision.riskLevel,
                protectedOperation: policyDecision.protectedOperation ?? .send,
                actionFingerprint: fingerprint,
                appProtectionProfile: policyDecision.appProtectionProfile
            )

            do {
                _ = try context.approvalStore.createRequest(request)
            } catch {
                let deniedDecision = policyDecision.withReason("Approval broker error: \(error.localizedDescription)")
                return blockedResult(
                    surface: surface,
                    taskID: taskID,
                    toolName: toolName,
                    intent: intent,
                    policyDecision: deniedDecision,
                    approvalRequestID: nil,
                    approvalStatus: "broker-error",
                    message: deniedDecision.reason ?? "Approval broker error"
                )
            }

            let pendingDecision = policyDecision.withApprovalRequest(id: request.id)
            return blockedResult(
                surface: surface,
                taskID: taskID,
                toolName: toolName,
                intent: intent,
                policyDecision: pendingDecision,
                approvalRequestID: request.id,
                approvalStatus: ApprovalStatus.pending.rawValue,
                message: "Action pending approval",
                projectMemoryRefs: projectMemoryRefs,
                experimentID: experimentID,
                candidateID: candidateID,
                sandboxPath: sandboxPath,
                selectedCandidate: selectedCandidate,
                experimentOutcome: experimentOutcome,
                architectureFindings: architectureFindings,
                refactorProposalID: refactorProposalID,
                knowledgeTier: knowledgeTier
            )
        }

        if !policyDecision.allowed {
            return blockedResult(
                surface: surface,
                taskID: taskID,
                toolName: toolName,
                intent: intent,
                policyDecision: policyDecision,
                approvalRequestID: nil,
                approvalStatus: nil,
                message: policyDecision.reason ?? "Action blocked by policy",
                projectMemoryRefs: projectMemoryRefs,
                experimentID: experimentID,
                candidateID: candidateID,
                sandboxPath: sandboxPath,
                selectedCandidate: selectedCandidate,
                experimentOutcome: experimentOutcome,
                architectureFindings: architectureFindings,
                refactorProposalID: refactorProposalID,
                knowledgeTier: knowledgeTier
            )
        }

        return executeVerified(
            surface: surface,
            taskID: taskID,
            toolName: toolName,
            intent: intent,
            selectedElementID: selectedElementID,
            selectedElementLabel: selectedElementLabel,
            candidateScore: candidateScore,
            candidateReasons: candidateReasons,
            candidateAmbiguityScore: candidateAmbiguityScore,
            policyDecision: policyDecision,
            approvalRequestID: nil,
            approvalOutcome: nil,
            plannerSource: plannerSource,
            plannerFamily: plannerFamily,
            pathEdgeIDs: pathEdgeIDs,
            currentEdgeID: currentEdgeID,
            recoveryTagged: recoveryTagged,
            recoveryStrategy: recoveryStrategy,
            recoverySource: recoverySource,
            projectMemoryRefs: projectMemoryRefs,
            experimentID: experimentID,
            candidateID: candidateID,
            sandboxPath: sandboxPath,
            selectedCandidate: selectedCandidate,
            experimentOutcome: experimentOutcome,
            architectureFindings: architectureFindings,
            refactorProposalID: refactorProposalID,
            knowledgeTier: knowledgeTier,
            execute: execute
        )
    }

    private func executeVerified(
        surface: RuntimeSurface,
        taskID: String?,
        toolName: String?,
        intent: ActionIntent,
        selectedElementID: String?,
        selectedElementLabel: String?,
        candidateScore: Double?,
        candidateReasons: [String],
        candidateAmbiguityScore: Double?,
        policyDecision: PolicyDecision,
        approvalRequestID: String?,
        approvalOutcome: String?,
        plannerSource: String?,
        plannerFamily: String?,
        pathEdgeIDs: [String]?,
        currentEdgeID: String?,
        recoveryTagged: Bool,
        recoveryStrategy: String?,
        recoverySource: String?,
        projectMemoryRefs: [String],
        experimentID: String?,
        candidateID: String?,
        sandboxPath: String?,
        selectedCandidate: Bool?,
        experimentOutcome: String?,
        architectureFindings: [String],
        refactorProposalID: String?,
        knowledgeTier: KnowledgeTier?,
        execute: () -> ToolResult
    ) -> ToolResult {
        var result = context.verifiedExecutor.run(
            taskID: taskID,
            toolName: toolName,
            intent: intent,
            selectedElementID: selectedElementID,
            selectedElementLabel: selectedElementLabel,
            candidateScore: candidateScore,
            candidateReasons: candidateReasons,
            candidateAmbiguityScore: candidateAmbiguityScore,
            surface: surface,
            policyDecision: policyDecision,
            approvalRequestID: approvalRequestID,
            approvalOutcome: approvalOutcome,
            plannerSource: plannerSource,
            plannerFamily: plannerFamily,
            pathEdgeIDs: pathEdgeIDs,
            currentEdgeID: currentEdgeID,
            recoveryTagged: recoveryTagged,
            recoveryStrategy: recoveryStrategy,
            recoverySource: recoverySource,
            projectMemoryRefs: projectMemoryRefs,
            experimentID: experimentID,
            candidateID: candidateID,
            sandboxPath: sandboxPath,
            selectedCandidate: selectedCandidate,
            experimentOutcome: experimentOutcome,
            architectureFindings: architectureFindings,
            refactorProposalID: refactorProposalID,
            knowledgeTier: knowledgeTier,
            execute: execute
        )

        // Enforcement: every action must pass through VerifiedActionExecutor.
        // The executor stamps executedThroughExecutor = true on every run().
        // Assert unconditionally — a missing key is itself a bypass signal.
        let _actionResultDict = result.data?["action_result"] as? [String: Any]
        precondition(
            _actionResultDict != nil && _actionResultDict?["executed_through_executor"] as? Bool == true,
            "[OracleRuntime] Trust boundary violated: action was not executed through VerifiedActionExecutor. "
                + "All environment-mutating actions must flow through VerifiedActionExecutor.run()."
        )

        if shouldRecordPostExecutionOutcome(from: result, policyDecision: policyDecision) {
            recordPostExecutionOutcome(from: result, policyDecision: policyDecision)
        }

        result = mergingPolicy(
            into: result,
            surface: surface,
            policyDecision: policyDecision,
            approvalRequestID: approvalRequestID,
            approvalStatus: approvalOutcome
        )
        return result
    }

    private func blockedResult(
        surface: RuntimeSurface,
        taskID: String?,
        toolName: String?,
        intent: ActionIntent,
        policyDecision: PolicyDecision,
        approvalRequestID: String?,
        approvalStatus: String?,
        message: String,
        projectMemoryRefs: [String] = [],
        experimentID: String? = nil,
        candidateID: String? = nil,
        sandboxPath: String? = nil,
        selectedCandidate: Bool? = nil,
        experimentOutcome: String? = nil,
        architectureFindings: [String] = [],
        refactorProposalID: String? = nil,
        knowledgeTier: KnowledgeTier? = nil
    ) -> ToolResult {
        let preObservation = ObservationBuilder.capture(appName: resolvedAppName(for: intent))
        let preHash = ObservationHash.hash(preObservation)
        let repositorySnapshot = repositorySnapshot(for: intent)
        let planningState = context.stateAbstraction.abstract(
            observation: preObservation,
            repositorySnapshot: repositorySnapshot,
            observationHash: preHash
        )

        let sessionID = context.traceRecorder.sessionID
        let traceURL = context.telemetry.recordBlockedTrace(
            sessionID: sessionID,
            taskID: taskID,
            toolName: toolName,
            intent: intent,
            policyDecision: policyDecision,
            approvalRequestID: approvalRequestID,
            approvalStatus: approvalStatus,
            planningState: planningState,
            preHash: preHash,
            repositorySnapshot: repositorySnapshot,
            surface: surface,
            message: message
        )

        let actionResult = ActionResult(
            success: false,
            verified: false,
            message: message,
            method: nil,
            verificationStatus: nil,
            failureClass: "policyBlocked",
            elapsedMs: 0,
            policyDecision: policyDecision,
            protectedOperation: policyDecision.protectedOperation?.rawValue,
            approvalRequestID: approvalRequestID,
            approvalStatus: approvalStatus,
            surface: surface.rawValue,
            appProtectionProfile: policyDecision.appProtectionProfile.rawValue,
            blockedByPolicy: true
        )

        var data: [String: Any] = [
            "action_result": actionResult.toDict(),
            "policy_decision": policyDecision.toDict(),
            "trace": [
                "schema_version": TraceSchemaVersion.current,
                "session_id": sessionID,
                "planning_state_id": planningState.id.rawValue,
                "file": traceURL?.path as Any,
                "failure_class": "policyBlocked",
            ],
        ]

        if let approvalRequestID {
            data["approval_request_id"] = approvalRequestID
        }
        if let approvalStatus {
            data["approval_status"] = approvalStatus
        }

        return ToolResult(
            success: false,
            data: data,
            error: message
        )
    }

    private func mergingPolicy(
        into result: ToolResult,
        surface: RuntimeSurface,
        policyDecision: PolicyDecision,
        approvalRequestID: String?,
        approvalStatus: String?
    ) -> ToolResult {
        var data = result.data ?? [:]
        data["policy_decision"] = policyDecision.toDict()
        if let approvalRequestID {
            data["approval_request_id"] = approvalRequestID
        }
        if let approvalStatus {
            data["approval_status"] = approvalStatus
        }
        data["surface"] = surface.rawValue

        if var actionResult = data["action_result"] as? [String: Any] {
            actionResult["protected_operation"] = policyDecision.protectedOperation?.rawValue as Any
            actionResult["approval_request_id"] = approvalRequestID as Any
            actionResult["approval_status"] = approvalStatus as Any
            actionResult["surface"] = surface.rawValue
            actionResult["app_protection_profile"] = policyDecision.appProtectionProfile.rawValue
            actionResult["blocked_by_policy"] = false
            data["action_result"] = actionResult
        }

        return ToolResult(
            success: result.success,
            data: data,
            error: result.error,
            suggestion: result.suggestion,
            context: result.context
        )
    }

    private func resolvedAppName(for intent: ActionIntent) -> String? {
        if intent.app != "unknown" {
            return intent.app
        }
        return ObservationBuilder.capture(appName: nil).app
    }

    private func shouldRecordPostExecutionOutcome(from result: ToolResult, policyDecision: PolicyDecision) -> Bool {
        guard policyDecision.blockedByPolicy == false else {
            return false
        }
        guard let actionResultDict = result.data?["action_result"] as? [String: Any],
              let actionResult = ActionResult.from(dict: actionResultDict)
        else {
            return false
        }
        if actionResult.blockedByPolicy {
            return false
        }
        if actionResult.approvalStatus == ApprovalStatus.pending.rawValue {
            return false
        }
        return true
    }

    private func recordPostExecutionOutcome(from result: ToolResult, policyDecision: PolicyDecision) {
        guard let data = result.data,
              let executionSemantics = data["execution_semantics"] as? [String: Any],
              let actionContractDict = executionSemantics["action_contract"] as? [String: Any],
              let actionContract = ExecutionSemanticsEncoder.decodeActionContract(from: actionContractDict),
              let transitionDict = executionSemantics["verified_transition"] as? [String: Any],
              let transition = ExecutionSemanticsEncoder.decodeTransition(from: transitionDict),
              let planning = data["planning"] as? [String: Any],
              let preStateDict = planning["pre_state"] as? [String: Any],
              let postStateDict = planning["post_state"] as? [String: Any],
              let preState = PlanningState.from(dict: preStateDict),
              let postState = PlanningState.from(dict: postStateDict),
              let actionResultDict = data["action_result"] as? [String: Any],
              let actionResult = ActionResult.from(dict: actionResultDict)
        else {
            return
        }

        let ranking = data["ranking"] as? [String: Any]
        let ambiguityScore = ranking?["ambiguity_score"] as? Double

        recordGraphOutcome(
            transition: transition,
            actionContract: actionContract,
            actionResult: actionResult,
            preState: preState,
            postState: postState,
            ambiguityScore: ambiguityScore
        )

        let observation = ObservationBuilder.capture(appName: nil)
        let observationHash = ObservationHash.hash(observation)
        let repositorySnapshot = transition.domain == "code"
            ? repositorySnapshot(forWorkspaceRoot: intentWorkspaceRoot(from: data))
            : nil
        let worldState = WorldState(
            observationHash: observationHash,
            planningState: context.stateAbstraction.abstract(
                observation: observation,
                repositorySnapshot: repositorySnapshot,
                observationHash: observationHash
            ),
            observation: observation,
            repositorySnapshot: repositorySnapshot
        )

        applyMemoryOutcome(
            transition: transition,
            actionResult: actionResult,
            policyDecision: policyDecision,
            worldState: worldState,
            observation: observation,
            repositorySnapshot: repositorySnapshot
        )
    }

    private func recordGraphOutcome(
        transition: VerifiedTransition,
        actionContract: ActionContract,
        actionResult: ActionResult,
        preState: PlanningState,
        postState: PlanningState,
        ambiguityScore: Double?
    ) {
        if actionResult.success, actionResult.verified {
            context.graphStore.recordTransition(
                transition,
                actionContract: actionContract,
                fromState: preState,
                toState: postState
            )
        } else if let failureRaw = actionResult.failureClass,
                  let failure = FailureClass(rawValue: failureRaw)
        {
            context.graphStore.recordFailure(
                state: preState,
                actionContract: actionContract,
                failure: failure,
                ambiguityScore: ambiguityScore,
                recoveryTagged: transition.recoveryTagged
            )
        } else {
            return
        }

        _ = context.graphStore.promoteEligibleEdges()
        _ = context.graphStore.pruneOrDemoteEdges()
    }

    private func applyMemoryOutcome(
        transition: VerifiedTransition,
        actionResult: ActionResult,
        policyDecision: PolicyDecision,
        worldState: WorldState,
        observation: Observation,
        repositorySnapshot: RepositorySnapshot?
    ) {
        if let protectedOperation = policyDecision.protectedOperation {
            context.memoryStore.recordProtectedOperation(
                app: observation.app ?? "unknown",
                operation: protectedOperation.rawValue
            )
        }

        if let protectedOperation = policyDecision.protectedOperation,
           actionResult.approvalStatus == "approved"
        {
            context.memoryStore.recordApproval(
                app: observation.app ?? "unknown",
                operation: protectedOperation.rawValue
            )
        }

        if actionResult.success, let focused = observation.focusedElement {
            if transition.domain == "code", let commandCategory = transition.commandCategory, let workspaceRoot = repositorySnapshot?.workspaceRoot {
                context.memoryStore.recordCommandResult(category: commandCategory, workspaceRoot: workspaceRoot, success: true)
            } else {
                MemoryUpdater.recordSuccess(element: focused, state: worldState, store: context.memoryStore)
            }
        } else if let failureRaw = actionResult.failureClass,
                  let failure = FailureClass(rawValue: failureRaw)
        {
            if transition.domain == "code", let commandCategory = transition.commandCategory, let workspaceRoot = repositorySnapshot?.workspaceRoot {
                context.memoryStore.recordCommandResult(category: commandCategory, workspaceRoot: workspaceRoot, success: false)
            }
            MemoryUpdater.recordFailure(failure: failure, state: worldState, store: context.memoryStore)
        }
    }

    public func makeExecutionDriver(
        surface: RuntimeSurface = .recipe,
        rawActionExecutor: @escaping @MainActor (ActionIntent) -> ToolResult
    ) -> RuntimeExecutionDriver {
        RuntimeExecutionDriver(
            runtime: self,
            surface: surface,
            rawActionExecutor: rawActionExecutor
        )
    }

    public func runAutonomous(
        goal: Goal,
        observationProvider: any ObservationProvider,
        surface: RuntimeSurface = .recipe,
        budget: LoopBudget = LoopBudget(),
        rawActionExecutor: @escaping @MainActor (ActionIntent) -> ToolResult
    ) async -> LoopOutcome {
        let loop = AgentLoop(
            observationProvider: observationProvider,
            executionDriver: makeExecutionDriver(
                surface: surface,
                rawActionExecutor: rawActionExecutor
            ),
            stateAbstraction: context.stateAbstraction,
            planner: MainPlanner(),
            graphStore: context.graphStore,
            policyEngine: context.policyEngine,
            recoveryEngine: context.recoveryEngine,
            memoryStore: context.memoryStore,
            stateMemoryIndex: context.stateMemoryIndex
        )
        return await loop.run(goal: goal, budget: budget, surface: surface)
    }

    private func repositorySnapshot(for intent: ActionIntent) -> RepositorySnapshot? {
        guard intent.agentKind == .code,
              let workspaceRoot = intent.workspaceRoot
        else {
            return nil
        }
        return repositorySnapshot(forWorkspaceRoot: workspaceRoot)
    }

    private func repositorySnapshot(forWorkspaceRoot workspaceRoot: String?) -> RepositorySnapshot? {
        guard let workspaceRoot else { return nil }
        return context.repositoryIndexer.indexIfNeeded(
            workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        )
    }

    private func intentWorkspaceRoot(from data: [String: Any]) -> String? {
        (data["code_execution"] as? [String: Any])?["workspace_root"] as? String
    }



    // MARK: - Search-centric action selection

    /// Run a search-centric action selection cycle.
    ///
    /// Instead of executing a single planner-selected step, this method:
    ///   1. Generates multiple candidates from memory, graph, and LLM
    ///   2. Evaluates each candidate through the verified executor
    ///   3. Selects the best verified result
    ///   4. Records metrics for the cycle
    ///
    /// - Parameters:
    ///   - compressedState: The current compressed UI state.
    ///   - abstractState: The current abstract task state.
    ///   - surface: The runtime surface for execution.
    ///   - llmSchemas: Optional LLM fallback schemas.
    ///   - execute: Closure that executes an ``ActionIntent`` and returns a ``ToolResult``.
    /// - Returns: The best verified ``CandidateResult``, or `nil` if no candidates were viable.
    public func searchBestAction(
        compressedState: CompressedUIState,
        abstractState: AbstractTaskState,
        surface: RuntimeSurface = .mcp,
        llmSchemas: [ActionSchema] = [],
        execute: (ActionIntent) -> ToolResult
    ) -> CandidateResult? {
        let critic = context.criticLoop
        let stateAbstractionEngine = context.stateAbstractionEngine

        var memoryCandidateCount = 0
        var graphCandidateCount = 0
        var llmCandidateCount = 0

        let result = context.searchController.search(
            compressedState: compressedState,
            abstractState: abstractState,
            planningStateID: abstractState.id.rawValue,
            llmSchemas: llmSchemas
        ) { candidate in
            // Track source distribution for metrics.
            switch candidate.source {
            case .memory: memoryCandidateCount += 1
            case .graph: graphCandidateCount += 1
            case .llmFallback: llmCandidateCount += 1
            }

            let intent = ActionIntent.fromSchema(candidate.schema)
            let start = Date()
            let toolResult = performAction(
                surface: surface,
                intent: intent,
                execute: { execute(intent) }
            )
            let elapsedMs = Date().timeIntervalSince(start) * 1000.0

            let observationAppName = intent.app == "unknown" ? compressedState.app : intent.app
            let postObservation = ObservationBuilder.capture(appName: observationAppName)
            let postCompressed = stateAbstractionEngine.compress(postObservation)
            let actionResult = ActionResult(
                success: toolResult.success,
                executedThroughExecutor: true
            )
            let verdict = critic.evaluate(
                preState: compressedState,
                postState: postCompressed,
                schema: candidate.schema,
                actionResult: actionResult
            )

            let score = verdict.outcome == .success ? 1.0 :
                         verdict.outcome == .partialSuccess ? 0.5 : 0.0

            // Record action metrics.
            context.telemetry.recordAction(
                success: verdict.outcome == .success,
                elapsedMs: elapsedMs,
                isPatch: candidate.schema.kind == .applyPatch
            )

            return CandidateResult(
                candidate: candidate,
                success: verdict.outcome == .success,
                score: score,
                criticOutcome: verdict.outcome,
                elapsedMs: elapsedMs,
                notes: verdict.notes
            )
        }

        // Record search cycle metrics.
        let totalCandidates = memoryCandidateCount + graphCandidateCount + llmCandidateCount
        context.telemetry.recordSearchCycle(
            candidatesGenerated: totalCandidates,
            memoryCandidates: memoryCandidateCount,
            graphCandidates: graphCandidateCount,
            llmFallbackCandidates: llmCandidateCount
        )

        return result
    }
}
