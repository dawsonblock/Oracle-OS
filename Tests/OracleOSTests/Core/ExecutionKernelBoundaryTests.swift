import Foundation
import Testing
@testable import OracleOS

@Suite("Execution Kernel Boundary")
struct ExecutionKernelBoundaryTests {
    @Test("ActionResult executed_through_executor round-trips through toDict")
    func stampedRoundTripDict() {
        let original = ActionResult(success: true, executedThroughExecutor: true)
        let dict = original.toDict()
        let recovered = ActionResult.from(dict: dict)
        #expect(recovered?.executedThroughExecutor == true)
    }

    @Test("ActionResult executed_through_executor absent in dict defaults to false")
    func missingKeyDefaultsFalse() {
        let partial: [String: Any] = ["success": true]
        let result = ActionResult.from(dict: partial)
        #expect(result?.executedThroughExecutor == false)
    }

    @Test("ActionIntent converts to typed Intent metadata")
    func actionIntentConvertsToTypedIntent() {
        let actionIntent = ActionIntent.click(
            app: "Mail",
            query: "Compose",
            role: "AXButton",
            domID: "compose-button",
            x: 10,
            y: 20,
            button: "left",
            count: 1
        )

        let intent = actionIntent.asIntent(additionalMetadata: ["toolName": "oracle_click"])
        #expect(intent.domain == .ui)
        #expect(intent.metadata["actionKind"] == "click")
        #expect(intent.metadata["toolName"] == "oracle_click")
        #expect(intent.metadata["domID"] == "compose-button")
    }

    @Test("ToolResult missing action_result key is detectable as bypass")
    func bareToolResultIsDetectable() {
        let bareResult = ToolResult(success: true, data: [:])
        let actionResultDict = bareResult.data?["action_result"] as? [String: Any]
        let stamped = actionResultDict != nil && actionResultDict?["executed_through_executor"] as? Bool == true
        #expect(stamped == false)
    }
}
