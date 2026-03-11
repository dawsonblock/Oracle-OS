import Foundation

@MainActor
public final class VerifiedActionExecutor {
    private let verificationTimeout: TimeInterval
    private let stateAbstraction: StateAbstraction
    private let traceRecorder: TraceRecorder?
    private let traceStore: TraceStore?
    private let artifactWriter: FailureArtifactWriter?

    public init(
        verificationTimeout: TimeInterval = 1.5,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        traceRecorder: TraceRecorder? = nil,
        traceStore: TraceStore? = nil,
        artifactWriter: FailureArtifactWriter? = nil
    ) {
        self.verificationTimeout = verificationTimeout
        self.stateAbstraction = stateAbstraction
        self.traceRecorder = traceRecorder
        self.traceStore = traceStore
        self.artifactWriter = artifactWriter
    }

    public func run(
        taskID: String? = nil,
        toolName: String? = nil,
        intent: ActionIntent,
        selectedElementID: String? = nil,
        selectedElementLabel: String? = nil,
        candidateScore: Double? = nil,
        candidateReasons: [String] = [],
        execute: () -> ToolResult
    ) -> ToolResult {
        let sessionID = traceRecorder?.sessionID ?? "no-session"
        let stepID = traceRecorder?.makeStepID() ?? 0
        let start = Date()
        let preObservation = ObservationBuilder.capture(appName: intent.app)
        let preHash = ObservationHash.hash(preObservation)
        let prePlanningState = stateAbstraction.abstract(
            observation: preObservation,
            observationHash: preHash
        )

        let raw = execute()
        let (postObservation, verification, timedOut) = captureVerifiedPostObservation(
            appName: intent.app,
            conditions: intent.postconditions
        )
        let postHash = ObservationHash.hash(postObservation)
        let postPlanningState = stateAbstraction.abstract(
            observation: postObservation,
            observationHash: postHash
        )
        let failureClass = classifyFailure(raw: raw, verification: verification, timedOut: timedOut)
        let verified = raw.success && verification.status != .failed
        let elapsedMs = Date().timeIntervalSince(start) * 1000.0
        let method = raw.data?["method"] as? String
        let actionContract = ActionContract.from(
            intent: intent,
            method: method,
            selectedElementLabel: selectedElementLabel
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
            postconditionClass: postconditionClass,
            verified: verified,
            failureClass: failureClass?.rawValue,
            latencyMs: Int(elapsedMs.rounded())
        )

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
            elapsedMs: elapsedMs
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
            preObservationHash: preHash,
            postObservationHash: postHash,
            planningStateID: prePlanningState.id.rawValue,
            beliefSnapshotID: nil,
            postcondition: describe(postconditions: intent.postconditions),
            postconditionClass: postconditionClass.rawValue,
            actionContractID: actionContract.id,
            executionMode: "verified-execution",
            verified: verified,
            success: verified,
            failureClass: failureClass?.rawValue,
            recoveryStrategy: nil,
            recoverySource: nil,
            elapsedMs: elapsedMs,
            screenshotPath: artifactSummary.screenshotPath,
            notes: TraceEnricher.mergedNotes(
                existing: artifactSummary.notes,
                planningStateID: prePlanningState.id,
                actionContractID: actionContract.id,
                postconditionClass: postconditionClass,
                executionMode: "verified-execution",
                recoverySource: nil
            )
        )

        traceRecorder?.record(event)
        let traceURL = try? traceStore?.append(event)

        var data = raw.data ?? [:]
        data["action_result"] = actionResult.toDict()
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
        ]
        if let tracePath = traceURL?.path {
            traceData["file"] = tracePath
        }
        if let failureClass {
            traceData["failure_class"] = failureClass.rawValue
        }
        data["trace"] = traceData
        data["observations"] = [
            "pre_hash": preHash,
            "post_hash": postHash,
        ]
        data["planning"] = [
            "pre_state_id": prePlanningState.id.rawValue,
            "post_state_id": postPlanningState.id.rawValue,
        ]
        data["execution_semantics"] = ExecutionSemanticsEncoder.encode(
            actionContract: actionContract,
            transition: verifiedTransition
        )

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
        raw: ToolResult,
        verification: VerificationSummary,
        timedOut: Bool
    ) -> FailureClass? {
        if !raw.success {
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
