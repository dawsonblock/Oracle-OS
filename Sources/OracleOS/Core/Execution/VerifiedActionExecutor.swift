import Foundation

@MainActor
public final class VerifiedActionExecutor {
    private let verificationTimeout: TimeInterval
    private let stateAbstraction: StateAbstraction
    private let stateAbstractionEngine: StateAbstractionEngine
    private let critic: CriticLoop
    private let traceRecorder: TraceRecorder?
    private let traceStore: TraceStore?
    private let artifactWriter: FailureArtifactWriter?
    private let graphStore: GraphStore?
    private let taskGraphStore: TaskGraphStore?
    private let stateMemoryIndex: StateMemoryIndex?
    private let planningGraphStore: PlanningGraphStore?

    public init(
        verificationTimeout: TimeInterval = 1.5,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        stateAbstractionEngine: StateAbstractionEngine = StateAbstractionEngine(),
        critic: CriticLoop = CriticLoop(),
        traceRecorder: TraceRecorder? = nil,
        traceStore: TraceStore? = nil,
        artifactWriter: FailureArtifactWriter? = nil,
        graphStore: GraphStore? = nil,
        taskGraphStore: TaskGraphStore? = nil,
        stateMemoryIndex: StateMemoryIndex? = nil,
        planningGraphStore: PlanningGraphStore? = nil
    ) {
        self.verificationTimeout = verificationTimeout
        self.stateAbstraction = stateAbstraction
        self.stateAbstractionEngine = stateAbstractionEngine
        self.critic = critic
        self.traceRecorder = traceRecorder
        self.traceStore = traceStore
        self.artifactWriter = artifactWriter
        self.graphStore = graphStore
        self.taskGraphStore = taskGraphStore
        self.stateMemoryIndex = stateMemoryIndex
        self.planningGraphStore = planningGraphStore
    }

    /// Execute an action within the verified trust boundary.
    ///
    /// This method is the **sole authority** for environment mutations.
    /// Every side-effect-producing closure must pass through `run()` so that
    /// pre/post observations are captured, the critic can judge the outcome,
    /// and the result is stamped with `executedThroughExecutor = true`.
    public func run(
        taskID: String? = nil,
        toolName: String? = nil,
        intent: ActionIntent,
        schema: ActionSchema? = nil,
        selectedElementID: String? = nil,
        selectedElementLabel: String? = nil,
        candidateScore: Double? = nil,
        candidateReasons: [String] = [],
        candidateAmbiguityScore: Double? = nil,
        surface: RuntimeSurface = .mcp,
        policyDecision: PolicyDecision? = nil,
        approvalRequestID: String? = nil,
        approvalOutcome: String? = nil,
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
        let sessionID = traceRecorder?.sessionID ?? "no-session"
        let stepID = traceRecorder?.makeStepID() ?? 0
        let start = Date()
        let preObservation = ObservationBuilder.capture(appName: intent.app)
        let preHash = ObservationHash.hash(preObservation)
        let preRepositorySnapshot = repositorySnapshot(for: intent)
        let prePlanningState = stateAbstraction.abstract(
            observation: preObservation,
            repositorySnapshot: preRepositorySnapshot,
            observationHash: preHash
        )

        let raw = execute()
        let (postObservation, verification, timedOut) = captureVerifiedPostObservation(
            appName: intent.app,
            conditions: intent.postconditions
        )
        let postHash = ObservationHash.hash(postObservation)
        let postRepositorySnapshot = repositorySnapshot(for: intent)
        let postPlanningState = stateAbstraction.abstract(
            observation: postObservation,
            repositorySnapshot: postRepositorySnapshot,
            observationHash: postHash
        )
        let failureClass = classifyFailure(intent: intent, raw: raw, verification: verification, timedOut: timedOut)
        let verified = raw.success && verification.status != .failed
        let elapsedMs = Date().timeIntervalSince(start) * 1000.0
        let method = raw.data?["method"] as? String
        let effectiveKnowledgeTier = knowledgeTier ?? (recoveryTagged ? .recovery : (plannerSource == PlannerSource.exploration.rawValue ? .exploration : .candidate))
        let actionContract = ActionContract.from(
            intent: intent,
            method: method,
            selectedElementLabel: selectedElementLabel,
            plannerFamily: plannerFamily ?? plannerSource
        )
        let postconditionClass = classifyPostconditionClass(
            intent: intent,
            verification: verification,
            raw: raw,
            failureClass: failureClass
        )
        let verifiedTransition = VerifiedTransition(
            fromPlanningStateID: prePlanningState.id,
            toPlanningStateID: postPlanningState.id,
            actionContractID: actionContract.id,
            agentKind: intent.agentKind,
            domain: intent.domain,
            workspaceRelativePath: intent.workspaceRelativePath,
            commandCategory: intent.commandCategory,
            plannerFamily: plannerFamily ?? plannerSource,
            postconditionClass: postconditionClass,
            verified: verified,
            failureClass: failureClass?.rawValue,
            latencyMs: Int(elapsedMs.rounded()),
            targetAmbiguityScore: candidateAmbiguityScore,
            recoveryTagged: recoveryTagged,
            approvalRequired: policyDecision?.requiresApproval ?? false,
            approvalOutcome: approvalOutcome,
            knowledgeTier: effectiveKnowledgeTier
        )
        let codeExecution = raw.data?["code_execution"] as? [String: Any]

        let artifactSummary = failureArtifacts(
            sessionID: sessionID,
            stepID: stepID,
            appName: intent.app,
            preObservation: preObservation,
            postObservation: postObservation,
            raw: raw,
            verification: verification,
            failureClass: failureClass
        )

        let actionResult = ActionResult(
            success: verified,
            verified: verified,
            message: raw.error ?? raw.suggestion,
            method: method,
            verificationStatus: verification.status,
            failureClass: failureClass?.rawValue,
            elapsedMs: elapsedMs,
            policyDecision: policyDecision,
            protectedOperation: policyDecision?.protectedOperation?.rawValue,
            approvalRequestID: approvalRequestID,
            approvalStatus: approvalOutcome,
            surface: surface.rawValue,
            appProtectionProfile: policyDecision?.appProtectionProfile.rawValue,
            blockedByPolicy: policyDecision?.blockedByPolicy ?? false,
            executedThroughExecutor: true
        )

        // --- Critic evaluation ---
        // Compress pre/post observations into semantic state for the critic.
        let preCompressed = stateAbstractionEngine.compress(preObservation)
        let postCompressed = stateAbstractionEngine.compress(postObservation)
        let criticVerdict = critic.evaluate(
            preState: preCompressed,
            postState: postCompressed,
            schema: schema,
            actionResult: actionResult
        )

        let event = TraceEvent(
            sessionID: sessionID,
            taskID: taskID,
            stepID: stepID,
            toolName: toolName,
            actionName: intent.action,
            actionTarget: intent.targetQuery ?? intent.elementID,
            actionText: intent.text,
            selectedElementID: selectedElementID ?? intent.elementID,
            selectedElementLabel: selectedElementLabel,
            candidateScore: candidateScore,
            candidateReasons: candidateReasons,
            ambiguityScore: candidateAmbiguityScore,
            preObservationHash: preHash,
            postObservationHash: postHash,
            planningStateID: prePlanningState.id.rawValue,
            beliefSnapshotID: nil,
            postcondition: describe(postconditions: intent.postconditions),
            postconditionClass: postconditionClass.rawValue,
            actionContractID: actionContract.id,
            executionMode: "verified-execution",
            plannerSource: plannerSource,
            pathEdgeIDs: pathEdgeIDs,
            currentEdgeID: currentEdgeID,
            verified: verified,
            success: verified,
            failureClass: failureClass?.rawValue,
            recoveryStrategy: recoveryStrategy,
            recoverySource: recoverySource,
            recoveryTagged: recoveryTagged,
            surface: surface.rawValue,
            policyMode: policyDecision?.policyMode.rawValue,
            protectedOperation: policyDecision?.protectedOperation?.rawValue,
            approvalRequestID: approvalRequestID,
            approvalOutcome: approvalOutcome,
            blockedByPolicy: policyDecision?.blockedByPolicy,
            appProfile: policyDecision?.appProtectionProfile.rawValue,
            agentKind: intent.agentKind.rawValue,
            domain: intent.domain,
            plannerFamily: plannerFamily ?? plannerSource,
            workspaceRelativePath: intent.workspaceRelativePath,
            commandCategory: intent.commandCategory,
            commandSummary: intent.commandSummary,
            repositorySnapshotID: codeExecution?["repository_snapshot_id"] as? String,
            buildResultSummary: codeExecution?["build_result_summary"] as? String,
            testResultSummary: codeExecution?["test_result_summary"] as? String,
            patchID: codeExecution?["patch_id"] as? String ?? raw.data?["patch_id"] as? String,
            projectMemoryRefs: projectMemoryRefs.isEmpty ? nil : projectMemoryRefs,
            experimentID: experimentID,
            candidateID: candidateID,
            sandboxPath: sandboxPath,
            selectedCandidate: selectedCandidate,
            experimentOutcome: experimentOutcome,
            architectureFindings: architectureFindings.isEmpty ? nil : architectureFindings,
            refactorProposalID: refactorProposalID,
            knowledgeTier: effectiveKnowledgeTier.rawValue,
            elapsedMs: elapsedMs,
            screenshotPath: artifactSummary.screenshotPath,
            notes: TraceEnricher.mergedNotes(
                existing: artifactSummary.notes,
                planningStateID: prePlanningState.id,
                actionContractID: actionContract.id,
                postconditionClass: postconditionClass,
                executionMode: "verified-execution",
                recoverySource: recoverySource
            )
        )

        traceRecorder?.record(event)
        let traceURL = try? traceStore?.append(event)

        // Record edge transition in the task graph when an edge ID is provided.
        // The critic verdict drives graph promotion/demotion: only critic-confirmed
        // successes promote an edge; failures and unknowns record a failed execution.
        if let taskGraphStore, let currentEdgeID {
            let postWorldState = WorldState(
                observationHash: postHash,
                planningState: postPlanningState,
                observation: postObservation,
                repositorySnapshot: postRepositorySnapshot
            )
            switch criticVerdict.outcome {
            case .success:
                taskGraphStore.recordVerifiedExecution(
                    edgeID: currentEdgeID,
                    resultWorldState: postWorldState,
                    latencyMs: Int(elapsedMs.rounded()),
                    cost: 0,
                    createdByAction: intent.action
                )
            case .partialSuccess:
                // Partial success still advances the graph but with a penalty
                // recorded as a failure so the edge's success probability drops.
                taskGraphStore.recordVerifiedExecution(
                    edgeID: currentEdgeID,
                    resultWorldState: postWorldState,
                    latencyMs: Int(elapsedMs.rounded()),
                    cost: 0,
                    createdByAction: intent.action
                )
                taskGraphStore.recordFailedExecution(
                    edgeID: currentEdgeID,
                    latencyMs: 0,
                    cost: 0
                )
            case .failure, .unknown:
                taskGraphStore.recordFailedExecution(
                    edgeID: currentEdgeID,
                    latencyMs: Int(elapsedMs.rounded()),
                    cost: 0
                )
            }
        }

        // --- Critic-driven state memory update ---
        // Record the action outcome in state memory so the planner can
        // consult historical success rates for the current state.
        if let stateMemoryIndex {
            let actionName = schema?.name ?? intent.action
            let succeeded = criticVerdict.outcome == .success
            stateMemoryIndex.record(
                state: preCompressed,
                actionName: actionName,
                success: succeeded
            )
        }

        // --- Critic-driven planning graph update ---
        // Feed verified outcomes back into the planning graph so candidate
        // ranking reflects real execution results.
        if let planningGraphStore, let schema {
            let preID = prePlanningState.id.rawValue
            let postID = postPlanningState.id.rawValue
            planningGraphStore.recordOutcome(
                fromState: preID,
                toState: postID,
                schema: schema,
                success: criticVerdict.outcome == .success,
                latencyMs: elapsedMs
            )
        }

        var data = raw.data ?? [:]
        data["action_result"] = actionResult.toDict()
        data["critic_verdict"] = criticVerdict.toDict()
        data["verification"] = [
            "status": verification.status.rawValue,
            "checks": verification.checks.map {
                [
                    "kind": $0.condition.kind.rawValue,
                    "target": $0.condition.target,
                    "expected": $0.condition.expected as Any,
                    "passed": $0.passed,
                    "detail": $0.detail as Any,
                ] as [String: Any]
            },
        ]
        var traceData: [String: Any] = [
            "schema_version": TraceSchemaVersion.current,
            "session_id": sessionID,
            "step_id": stepID,
            "planning_state_id": prePlanningState.id.rawValue,
            "action_contract_id": actionContract.id,
            "postcondition_class": postconditionClass.rawValue,
            "surface": surface.rawValue,
        ]
        if let tracePath = traceURL?.path {
            traceData["file"] = tracePath
        }
        if let failureClass {
            traceData["failure_class"] = failureClass.rawValue
        }
        if let plannerSource {
            traceData["planner_source"] = plannerSource
        }
        if let pathEdgeIDs {
            traceData["path_edge_ids"] = pathEdgeIDs
        }
        if let currentEdgeID {
            traceData["current_edge_id"] = currentEdgeID
        }
        if let candidateAmbiguityScore {
            traceData["ambiguity_score"] = candidateAmbiguityScore
        }
        traceData["recovery_tagged"] = recoveryTagged
        traceData["critic_outcome"] = criticVerdict.outcome.rawValue
        traceData["critic_needs_recovery"] = criticVerdict.needsRecovery
        if let policyDecision {
            traceData["policy_mode"] = policyDecision.policyMode.rawValue
            traceData["app_profile"] = policyDecision.appProtectionProfile.rawValue
            traceData["protected_operation"] = policyDecision.protectedOperation?.rawValue as Any
            traceData["blocked_by_policy"] = policyDecision.blockedByPolicy
        }
        if let approvalRequestID {
            traceData["approval_request_id"] = approvalRequestID
        }
        if let approvalOutcome {
            traceData["approval_outcome"] = approvalOutcome
        }
        traceData["agent_kind"] = intent.agentKind.rawValue
        traceData["domain"] = intent.domain
        traceData["planner_family"] = plannerFamily as Any
        traceData["workspace_relative_path"] = intent.workspaceRelativePath as Any
        traceData["command_category"] = intent.commandCategory as Any
        traceData["command_summary"] = intent.commandSummary as Any
        traceData["repository_snapshot_id"] = codeExecution?["repository_snapshot_id"] as Any
        traceData["build_result_summary"] = codeExecution?["build_result_summary"] as Any
        traceData["test_result_summary"] = codeExecution?["test_result_summary"] as Any
        traceData["patch_id"] = codeExecution?["patch_id"] as Any
        if !projectMemoryRefs.isEmpty {
            traceData["project_memory_refs"] = projectMemoryRefs
        }
        traceData["experiment_id"] = experimentID as Any
        traceData["candidate_id"] = candidateID as Any
        traceData["sandbox_path"] = sandboxPath as Any
        traceData["selected_candidate"] = selectedCandidate as Any
        traceData["experiment_outcome"] = experimentOutcome as Any
        if !architectureFindings.isEmpty {
            traceData["architecture_findings"] = architectureFindings
        }
        traceData["refactor_proposal_id"] = refactorProposalID as Any
        traceData["knowledge_tier"] = effectiveKnowledgeTier.rawValue
        data["trace"] = traceData
        data["observations"] = [
            "pre_hash": preHash,
            "post_hash": postHash,
        ]
        data["planning"] = [
            "pre_state_id": prePlanningState.id.rawValue,
            "post_state_id": postPlanningState.id.rawValue,
            "pre_state": prePlanningState.toDict(),
            "post_state": postPlanningState.toDict(),
            "pre_repository_snapshot_id": preRepositorySnapshot?.id as Any,
            "post_repository_snapshot_id": postRepositorySnapshot?.id as Any,
        ]
        data["ranking"] = [
            "selected_element_id": selectedElementID ?? intent.elementID as Any,
            "selected_element_label": selectedElementLabel as Any,
            "score": candidateScore as Any,
            "reasons": candidateReasons,
            "ambiguity_score": candidateAmbiguityScore as Any,
        ]
        data["execution_semantics"] = ExecutionSemanticsEncoder.encode(
            actionContract: actionContract,
            transition: verifiedTransition
        )
        if let codeExecution {
            data["code_execution"] = codeExecution
        }
        if let policyDecision {
            data["policy_decision"] = policyDecision.toDict()
        }
        if let approvalRequestID {
            data["approval_request_id"] = approvalRequestID
        }
        if let approvalOutcome {
            data["approval_status"] = approvalOutcome
        }
        data["surface"] = surface.rawValue

        let finalError: String?
        if raw.success, verification.status == .failed {
            let detail = verification.checks.first(where: { !$0.passed })?.detail
                ?? (timedOut ? "Postcondition verification timed out" : "Postcondition verification failed")
            finalError = detail
        } else {
            finalError = raw.error
        }

        return ToolResult(
            success: verified,
            data: data,
            error: finalError,
            suggestion: raw.suggestion,
            context: raw.context
        )
    }

    public static func run(
        intent: ActionIntent,
        execute: () -> ToolResult
    ) -> ToolResult {
        VerifiedActionExecutor().run(intent: intent, execute: execute)
    }

    private func captureVerifiedPostObservation(
        appName: String,
        conditions: [Postcondition]
    ) -> (Observation, VerificationSummary, Bool) {
        var latestObservation = ObservationBuilder.capture(appName: appName)
        var latestVerification = ActionVerifier.verify(post: latestObservation, conditions: conditions)

        guard !conditions.isEmpty, latestVerification.status == .failed else {
            return (latestObservation, latestVerification, false)
        }

        let satisfied = WaitEngine.wait(timeout: verificationTimeout) {
            latestObservation = ObservationBuilder.capture(appName: appName)
            latestVerification = ActionVerifier.verify(post: latestObservation, conditions: conditions)
            return latestVerification.status != .failed
        }

        if !satisfied {
            latestObservation = ObservationBuilder.capture(appName: appName)
            latestVerification = ActionVerifier.verify(post: latestObservation, conditions: conditions)
        }

        return (latestObservation, latestVerification, !satisfied)
    }

    private func classifyFailure(
        intent: ActionIntent,
        raw: ToolResult,
        verification: VerificationSummary,
        timedOut: Bool
    ) -> FailureClass? {
        if !raw.success {
            if intent.agentKind == .code {
                switch intent.commandCategory {
                case CodeCommandCategory.build.rawValue, CodeCommandCategory.linter.rawValue:
                    return .buildFailed
                case CodeCommandCategory.test.rawValue, CodeCommandCategory.parseTestFailure.rawValue:
                    return .testFailed
                case CodeCommandCategory.editFile.rawValue, CodeCommandCategory.writeFile.rawValue, CodeCommandCategory.generatePatch.rawValue:
                    return .patchApplyFailed
                case CodeCommandCategory.gitPush.rawValue:
                    return .gitPolicyBlocked
                default:
                    if intent.workspaceRelativePath?.hasPrefix("/") == true || intent.workspaceRelativePath?.contains("../") == true {
                        return .workspaceScopeViolation
                    }
                }
            }
            let error = raw.error?.lowercased() ?? ""
            if error.contains("not found") {
                return .elementNotFound
            }
            if error.contains("focus") {
                return .wrongFocus
            }
            return .actionFailed
        }

        if verification.status == .failed {
            if verification.checks.contains(where: {
                $0.condition.kind == .elementFocused || $0.condition.kind == .appFrontmost
            }) {
                return .wrongFocus
            }
            if verification.checks.contains(where: {
                $0.condition.kind == .windowTitleContains || $0.condition.kind == .urlContains
            }) {
                return .navigationFailed
            }
            if timedOut {
                return .staleObservation
            }
            return .verificationFailed
        }

        return nil
    }

    private func describe(postconditions: [Postcondition]) -> String? {
        guard !postconditions.isEmpty else { return nil }
        return postconditions.map {
            if let expected = $0.expected {
                return "\($0.kind.rawValue):\($0.target)=\(expected)"
            }
            return "\($0.kind.rawValue):\($0.target)"
        }.joined(separator: ", ")
    }

    private func classifyPostconditionClass(
        intent: ActionIntent,
        verification: VerificationSummary,
        raw: ToolResult,
        failureClass: FailureClass?
    ) -> PostconditionClass {
        if failureClass != nil || !raw.success {
            return .actionFailed
        }

        if verification.checks.contains(where: { $0.passed && $0.condition.kind == .urlContains }) {
            return .navigationOccurred
        }
        if verification.checks.contains(where: { $0.passed && $0.condition.kind == .elementAppeared }) {
            return .elementAppeared
        }
        if verification.checks.contains(where: { $0.passed && $0.condition.kind == .elementDisappeared }) {
            return .elementDisappeared
        }
        if verification.checks.contains(where: { $0.passed && $0.condition.kind == .elementValueEquals }) {
            return .textChanged
        }
        if verification.checks.contains(where: { $0.passed && $0.condition.kind == .elementFocused }) {
            return .focusChanged
        }

        if intent.postconditions.contains(where: { $0.kind == .elementAppeared }) {
            return .elementAppeared
        }
        if intent.postconditions.contains(where: { $0.kind == .elementDisappeared }) {
            return .elementDisappeared
        }
        if intent.postconditions.contains(where: { $0.kind == .urlContains }) {
            return .navigationOccurred
        }
        if intent.postconditions.contains(where: { $0.kind == .elementValueEquals }) {
            return .textChanged
        }
        if intent.postconditions.contains(where: { $0.kind == .elementFocused || $0.kind == .appFrontmost }) {
            return .focusChanged
        }

        return .unknown
    }

    private func repositorySnapshot(for intent: ActionIntent) -> RepositorySnapshot? {
        guard intent.agentKind == .code,
              let workspaceRoot = intent.workspaceRoot
        else {
            return nil
        }

        return RepositoryIndexer().indexIfNeeded(
            workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        )
    }

    private func failureArtifacts(
        sessionID: String,
        stepID: Int,
        appName: String?,
        preObservation: Observation,
        postObservation: Observation,
        raw: ToolResult,
        verification: VerificationSummary,
        failureClass: FailureClass?
    ) -> FailureArtifactSummary {
        guard failureClass != nil else {
            return FailureArtifactSummary(screenshotPath: nil, notes: nil)
        }

        let prePath = artifactWriter?.writeObservationArtifact(
            sessionID: sessionID,
            stepID: stepID,
            name: "pre-observation",
            observation: preObservation
        )
        let postPath = artifactWriter?.writeObservationArtifact(
            sessionID: sessionID,
            stepID: stepID,
            name: "post-observation",
            observation: postObservation
        )

        let failureNotes = [
            raw.error,
            raw.suggestion,
            verification.checks.first(where: { !$0.passed })?.detail,
        ]
            .compactMap { $0 }
            .joined(separator: "\n")

        let errorPath = artifactWriter?.writeTextArtifact(
            sessionID: sessionID,
            stepID: stepID,
            name: "error",
            contents: failureNotes.isEmpty ? "Unknown failure" : failureNotes
        )
        let screenshotPath = artifactWriter?.writeScreenshotArtifact(
            sessionID: sessionID,
            stepID: stepID,
            appName: appName
        )

        let notes = [
            failureNotes.isEmpty ? nil : failureNotes,
            prePath.map { "pre_observation=\($0)" },
            postPath.map { "post_observation=\($0)" },
            errorPath.map { "error_artifact=\($0)" },
            screenshotPath.map { "screenshot=\($0)" },
        ]
            .compactMap { $0 }
            .joined(separator: " | ")

        return FailureArtifactSummary(
            screenshotPath: screenshotPath,
            notes: notes.isEmpty ? nil : notes
        )
    }
}

private struct FailureArtifactSummary {
    let screenshotPath: String?
    let notes: String?
}
