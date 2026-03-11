import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Safe Runtime")
struct SafeRuntimeTests {

    @Test("Policy allows low-risk focus in confirm-risky mode")
    func policyAllowsLowRiskFocus() {
        let engine = PolicyEngine(mode: .confirmRisky)
        let decision = engine.evaluate(
            intent: .focus(app: "Finder"),
            context: PolicyEvaluationContext(surface: .mcp, toolName: "ghost_focus", appName: "Finder")
        )

        #expect(decision.allowed)
        #expect(decision.requiresApproval == false)
        #expect(decision.blockedByPolicy == false)
    }

    @Test("Policy requires approval for send actions in browser contexts")
    func policyRequiresApprovalForSend() {
        let engine = PolicyEngine(mode: .confirmRisky)
        let intent = ActionIntent.click(app: "Google Chrome", query: "Send")
        let decision = engine.evaluate(
            intent: intent,
            context: PolicyEvaluationContext(surface: .mcp, toolName: "ghost_click", appName: "Google Chrome")
        )

        #expect(decision.allowed == false)
        #expect(decision.requiresApproval)
        #expect(decision.protectedOperation == .send)
        #expect(decision.blockedByPolicy == false)
    }

    @Test("Policy blocks terminal interaction by default")
    func policyBlocksTerminalControl() {
        let engine = PolicyEngine(mode: .confirmRisky)
        let decision = engine.evaluate(
            intent: .press(app: "Terminal", key: "return"),
            context: PolicyEvaluationContext(surface: .cli, toolName: "ghost_press", appName: "Terminal")
        )

        #expect(decision.allowed == false)
        #expect(decision.blockedByPolicy)
        #expect(decision.protectedOperation == .terminalControl)
    }

    @Test("Approval receipts are single use")
    func approvalReceiptsSingleUse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ApprovalStore(rootDirectory: root)
        let request = ApprovalRequest(
            surface: .controller,
            toolName: "ghost_click",
            appName: "Google Chrome",
            displayTitle: "Click Send",
            reason: "Action requires approval",
            riskLevel: .risky,
            protectedOperation: .send,
            actionFingerprint: "fingerprint-send",
            appProtectionProfile: .confirmRisky
        )

        _ = try store.createRequest(request)
        _ = try store.approve(requestID: request.id)

        let firstReceipt = store.consumeApprovedReceipt(requestID: request.id, actionFingerprint: "fingerprint-send")
        let secondReceipt = store.consumeApprovedReceipt(requestID: request.id, actionFingerprint: "fingerprint-send")

        #expect(firstReceipt != nil)
        #expect(firstReceipt?.consumed == true)
        #expect(secondReceipt == nil)
    }

    @Test("Runtime fails closed when risky action has no controller approval path")
    func runtimeFailsClosedWithoutController() {
        let runtime = makeRuntime()
        let result = runtime.performAction(
            surface: .mcp,
            taskID: "test-task",
            toolName: "ghost_click",
            intent: .click(app: "Google Chrome", query: "Send")
        ) {
            ToolResult(success: true, data: ["method": "synthetic"])
        }

        #expect(result.success == false)
        #expect(result.data?["approval_status"] as? String == "unavailable")
        #expect((result.data?["policy_decision"] as? [String: Any])?["requires_approval"] as? Bool == true)
    }

    @Test("Runtime creates pending approval when controller heartbeat is active")
    func runtimeCreatesPendingApproval() {
        let runtime = makeRuntime(controllerConnected: true)
        let result = runtime.performAction(
            surface: .mcp,
            taskID: "test-task",
            toolName: "ghost_click",
            intent: .click(app: "Google Chrome", query: "Send")
        ) {
            ToolResult(success: true, data: ["method": "synthetic"])
        }

        #expect(result.success == false)
        #expect(result.data?["approval_status"] as? String == ApprovalStatus.pending.rawValue)
        #expect((result.data?["approval_request_id"] as? String)?.isEmpty == false)
    }

    private func makeRuntime(controllerConnected: Bool = false) -> OracleRuntime {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let traceRecorder = TraceRecorder()
        let traceStore = TraceStore(directoryURL: root.appendingPathComponent("traces", isDirectory: true))
        let artifactWriter = FailureArtifactWriter(baseURL: root.appendingPathComponent("artifacts", isDirectory: true))
        let approvalStore = ApprovalStore(rootDirectory: root.appendingPathComponent("approvals", isDirectory: true))

        if controllerConnected {
            approvalStore.writeControllerHeartbeat(sessionID: "controller-test")
        }

        let context = RuntimeContext(
            config: .live(),
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter,
            verifiedExecutor: VerifiedActionExecutor(
                traceRecorder: traceRecorder,
                traceStore: traceStore,
                artifactWriter: artifactWriter
            ),
            policyEngine: PolicyEngine(mode: .confirmRisky),
            approvalStore: approvalStore
        )

        return OracleRuntime(context: context)
    }
}
