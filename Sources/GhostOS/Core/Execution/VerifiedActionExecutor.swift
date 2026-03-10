import Foundation

@MainActor
public enum VerifiedActionExecutor {
    public static func run(
        intent: ActionIntent,
        execute: () -> ToolResult
    ) -> ToolResult {
        let preObservation = ObservationBuilder.capture(appName: intent.app)
        let start = Date()
        let raw = execute()
        let postObservation = ObservationBuilder.capture(appName: intent.app)
        let verification = ActionVerifier.verify(post: postObservation, conditions: intent.postconditions)
        let failureClass = classifyFailure(raw: raw, verification: verification)
        let finalSuccess = raw.success && verification.status != .failed
        let artifacts = failureClass != nil
            ? FailureArtifactWriter.capture(
                appName: intent.app,
                actionName: intent.name,
                pre: preObservation,
                post: postObservation
            )
            : nil

        let actionResult = ActionResult(
            success: finalSuccess,
            message: raw.error ?? raw.suggestion,
            method: raw.data?["method"] as? String,
            verificationStatus: verification.status,
            failureClass: failureClass?.rawValue
        )

        let event = TraceEvent(
            sessionID: TraceRecorder.shared.sessionID,
            intent: intent,
            result: actionResult,
            preObservationHash: preObservation.stableHash(),
            postObservationHash: postObservation.stableHash(),
            verification: verification,
            elapsedMs: Int(Date().timeIntervalSince(start) * 1000),
            failureClass: failureClass?.rawValue,
            artifacts: artifacts
        )
        let traceURL = TraceRecorder.shared.record(event)

        var data = raw.data ?? [:]
        data["verification"] = [
            "status": verification.status.rawValue,
            "checks": verification.checks.map {
                [
                    "kind": $0.condition.kind.rawValue,
                    "target": $0.condition.target as Any,
                    "expected": $0.condition.expected as Any,
                    "passed": $0.passed,
                    "detail": $0.detail as Any,
                ] as [String: Any]
            },
        ]
        data["trace"] = [
            "session_id": TraceRecorder.shared.sessionID,
            "file": traceURL?.path as Any,
            "failure_class": failureClass?.rawValue as Any,
        ]
        data["observations"] = [
            "pre_hash": preObservation.stableHash(),
            "post_hash": postObservation.stableHash(),
        ]

        let finalError: String?
        if raw.success, verification.status == .failed {
            let detail = verification.checks.first(where: { !$0.passed })?.detail ?? "Postcondition verification failed"
            finalError = detail
        } else {
            finalError = raw.error
        }

        return ToolResult(
            success: finalSuccess,
            data: data,
            error: finalError,
            suggestion: raw.suggestion,
            context: raw.context
        )
    }

    private static func classifyFailure(
        raw: ToolResult,
        verification: VerificationSummary
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
            if verification.checks.contains(where: { $0.condition.kind == .elementFocused }) {
                return .wrongFocus
            }
            return .verificationFailed
        }

        return nil
    }
}
