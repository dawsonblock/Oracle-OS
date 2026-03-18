import Foundation
import Combine

/// Bridges the AgentLoop execution path to the IntentAPI spine.
///
/// Translates ActionIntent → Intent → submitIntent, routing all execution
/// through the IntentAPI-based RuntimeOrchestrator.
@MainActor
public final class RuntimeExecutionDriver: AgentExecutionDriver {
    private let surface: RuntimeSurface
    private let intentAPI: any IntentAPI

    /// Preferred init — translates ActionIntent to Intent and submits via IntentAPI.
    /// This is a pure translator: it converts external input into Intent and forwards it.
    public init(
        intentAPI: any IntentAPI,
        surface: RuntimeSurface = .recipe
    ) {
        self.intentAPI = intentAPI
        self.surface = surface
    }

    public func execute(
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult {
        return executeViaIntentAPI(intentAPI, intent: intent, plannerDecision: plannerDecision)
    }

    // MARK: - IntentAPI translation path

    /// Translates ActionIntent to the typed Intent model and submits via IntentAPI.
    /// This is the approved path — no direct executor calls.
    private func executeViaIntentAPI(
        _ api: any IntentAPI,
        intent: ActionIntent,
        plannerDecision: PlannerDecision
    ) -> ToolResult {
        let domain: IntentDomain = intent.agentKind == .code ? .code :
            (intent.agentKind == .mixed ? .system : .ui)

        let typedIntent = Intent(
            domain: domain,
            objective: intent.name,
            metadata: ["query": intent.query ?? intent.text ?? intent.name]
        )

        // Submit intent via API — the sole approved execution gateway
        var result: ToolResult = ToolResult(success: false, error: "IntentAPI submission pending")
        let group = DispatchGroup()
        group.enter()
        Task { @MainActor in
            do {
                let response = try await api.submitIntent(typedIntent)
                result = ToolResult(
                    success: response.outcome == .success || response.outcome == .skipped,
                    data: ["summary": response.summary, "cycleID": response.cycleID.uuidString],
                    error: response.outcome == .failed ? response.summary : nil
                )
            } catch {
                result = ToolResult(success: false, error: error.localizedDescription)
            }
            group.leave()
        }
        group.wait()
        return result
    }
}
