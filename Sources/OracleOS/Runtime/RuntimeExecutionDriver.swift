import Foundation

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
        executeViaIntentAPI(
            intentAPI,
            intent: intent,
            plannerDecision: plannerDecision,
            selectedCandidate: selectedCandidate
        )
    }

    // MARK: - IntentAPI translation path

    /// Translates ActionIntent to the typed Intent model and submits via IntentAPI.
    /// This is the approved path — no direct executor calls.
    private func executeViaIntentAPI(
        _ api: any IntentAPI,
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult {
        let domain: IntentDomain = intent.agentKind == .code ? .code :
            (intent.agentKind == .mixed ? .system : .ui)

        var metadata = [
            "query": intent.query ?? intent.text ?? intent.name,
            "source": "runtime-execution-driver",
            "plannerSource": plannerDecision.source.rawValue,
            "plannerFamily": plannerDecision.plannerFamily.rawValue,
        ]
        if let selectedCandidate {
            metadata["selectedElementID"] = selectedCandidate.element.id
            metadata["selectedElementLabel"] = selectedCandidate.element.label
        }
        if let encodedIntent = Self.encodeActionIntent(intent) {
            metadata["action_intent_base64"] = encodedIntent
        }

        let typedIntent = Intent(
            domain: domain,
            objective: intent.name,
            metadata: metadata
        )

        // Submit intent via API — the sole approved execution gateway
        var result: ToolResult = ToolResult(success: false, error: "IntentAPI submission pending")
        let resultLock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            do {
                let response = try await api.submitIntent(typedIntent)
                resultLock.lock()
                result = ToolResult(
                    success: response.outcome == .success || response.outcome == .skipped,
                    data: ["summary": response.summary, "cycleID": response.cycleID.uuidString],
                    error: response.outcome == .failed ? response.summary : nil
                )
                resultLock.unlock()
            } catch {
                resultLock.lock()
                result = ToolResult(success: false, error: error.localizedDescription)
                resultLock.unlock()
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private static func encodeActionIntent(_ intent: ActionIntent) -> String? {
        guard let data = try? JSONEncoder().encode(intent) else {
            return nil
        }
        return data.base64EncodedString()
    }
}
