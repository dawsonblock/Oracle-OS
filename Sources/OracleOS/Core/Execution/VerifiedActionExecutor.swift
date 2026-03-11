import Foundation

@MainActor
public final class VerifiedActionExecutor {
    private let verificationTimeout: TimeInterval
    private let traceRecorder: TraceRecorder?
    private let traceStore: TraceStore?
    private let artifactWriter: FailureArtifactWriter?

    public init(
        verificationTimeout: TimeInterval = 1.5,
        traceRecorder: TraceRecorder? = nil,
        traceStore: TraceStore? = nil,
        artifactWriter: FailureArtifactWriter? = nil
    ) {
        self.verificationTimeout = verificationTimeout
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

        let raw = execute()
        let (postObservation, verification, timedOut) = captureVerifiedPostObservation(
            appName: intent.app,
            conditions: intent.postconditions
        )
        let postHash = ObservationHash.hash(postObservation)
        let failureClass = classifyFailure(raw: raw, verification: verification, timedOut: timedOut)
        let verified = raw.success && verification.status != .failed
        let elapsedMs = Date().timeIntervalSince(start) * 1000.0

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
            method: raw.data?["method"] as? String,
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
            postcondition: describe(postconditions: intent.postconditions),
            verified: verified,
            success: verified,
            failureClass: failureClass?.rawValue,
            recoveryStrategy: nil,
            elapsedMs: elapsedMs,
            screenshotPath: artifactSummary.screenshotPath,
            notes: artifactSummary.notes
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
        data["trace"] = [
            "session_id": sessionID,
            "step_id": stepID,
            "file": traceURL?.path as Any,
            "failure_class": failureClass?.rawValue as Any,
        ]
        data["observations"] = [
            "pre_hash": preHash,
            "post_hash": postHash,
        ]

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
