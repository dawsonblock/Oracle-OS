import Foundation

@MainActor
public final class OracleRuntime {
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
        execute: () -> ToolResult
    ) -> ToolResult {
        let appName = resolvedAppName(for: intent)
        let policyContext = PolicyEvaluationContext(
            surface: surface,
            toolName: toolName,
            appName: appName
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
                    policyDecision: policyDecision,
                    approvalRequestID: approvalRequestID,
                    approvalOutcome: receipt.consumed ? "approved" : "pending",
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
                message: "Action pending approval"
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
                message: policyDecision.reason ?? "Action blocked by policy"
            )
        }

        return executeVerified(
            surface: surface,
            taskID: taskID,
            toolName: toolName,
            intent: intent,
            policyDecision: policyDecision,
            approvalRequestID: nil,
            approvalOutcome: nil,
            execute: execute
        )
    }

    private func executeVerified(
        surface: RuntimeSurface,
        taskID: String?,
        toolName: String?,
        intent: ActionIntent,
        policyDecision: PolicyDecision,
        approvalRequestID: String?,
        approvalOutcome: String?,
        execute: () -> ToolResult
    ) -> ToolResult {
        var result = context.verifiedExecutor.run(
            taskID: taskID,
            toolName: toolName,
            intent: intent,
            surface: surface,
            policyDecision: policyDecision,
            approvalRequestID: approvalRequestID,
            approvalOutcome: approvalOutcome,
            execute: execute
        )

        if shouldLearn(from: result, policyDecision: policyDecision) {
            recordLearning(from: result, policyDecision: policyDecision)
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
        message: String
    ) -> ToolResult {
        let preObservation = ObservationBuilder.capture(appName: resolvedAppName(for: intent))
        let preHash = ObservationHash.hash(preObservation)
        let planningState = context.stateAbstraction.abstract(
            observation: preObservation,
            observationHash: preHash
        )
        let stepID = context.traceRecorder.makeStepID()
        let sessionID = context.traceRecorder.sessionID

        let event = TraceEvent(
            sessionID: sessionID,
            taskID: taskID,
            stepID: stepID,
            toolName: toolName,
            actionName: intent.action,
            actionTarget: intent.targetQuery ?? intent.elementID,
            actionText: policyDecision.protectedOperation == .credentialEntry ? nil : intent.text,
            selectedElementID: intent.elementID,
            selectedElementLabel: nil,
            candidateScore: nil,
            candidateReasons: [],
            preObservationHash: preHash,
            postObservationHash: preHash,
            planningStateID: planningState.id.rawValue,
            beliefSnapshotID: nil,
            postcondition: nil,
            postconditionClass: nil,
            actionContractID: nil,
            executionMode: "policy-\(approvalStatus == ApprovalStatus.pending.rawValue ? "pending" : "blocked")",
            verified: false,
            success: false,
            failureClass: "policyBlocked",
            recoveryStrategy: nil,
            recoverySource: nil,
            surface: surface.rawValue,
            policyMode: policyDecision.policyMode.rawValue,
            protectedOperation: policyDecision.protectedOperation?.rawValue,
            approvalRequestID: approvalRequestID,
            approvalOutcome: approvalStatus,
            blockedByPolicy: true,
            appProfile: policyDecision.appProtectionProfile.rawValue,
            elapsedMs: 0,
            screenshotPath: nil,
            notes: message
        )

        context.traceRecorder.record(event)
        let traceURL = try? context.traceStore.append(event)

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
                "step_id": stepID,
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

    private func shouldLearn(from result: ToolResult, policyDecision: PolicyDecision) -> Bool {
        guard result.success,
              (result.data?["action_result"] as? [String: Any])?["verified"] as? Bool == true
        else {
            return false
        }

        guard let protectedOperation = policyDecision.protectedOperation else {
            return true
        }

        return policyDecision.requiresApproval == false || protectedOperation == .send
    }

    private func recordLearning(from result: ToolResult, policyDecision: PolicyDecision) {
        guard let data = result.data,
              let executionSemantics = data["execution_semantics"] as? [String: Any],
              let actionContractDict = executionSemantics["action_contract"] as? [String: Any],
              let transitionDict = executionSemantics["verified_transition"] as? [String: Any],
              let actionContract = ExecutionSemanticsEncoder.decodeActionContract(from: actionContractDict),
              let transition = ExecutionSemanticsEncoder.decodeTransition(from: transitionDict)
        else {
            return
        }

        context.graphStore.recordTransition(transition, actionContract: actionContract)

        if let observationDict = data["observations"] as? [String: Any],
           let observationHash = observationDict["post_hash"] as? String
        {
            let observation = ObservationBuilder.capture(appName: nil)
            let worldState = WorldState(
                observationHash: observationHash,
                planningState: context.stateAbstraction.abstract(observation: observation, observationHash: observationHash),
                observation: observation
            )

            if let protectedOperation = policyDecision.protectedOperation {
                context.memoryStore.recordProtectedOperation(
                    app: observation.app ?? "unknown",
                    operation: protectedOperation.rawValue
                )
            }

            if let focused = observation.focusedElement {
                MemoryUpdater.recordSuccess(element: focused, state: worldState, store: context.memoryStore)
            }
        }
    }
}
