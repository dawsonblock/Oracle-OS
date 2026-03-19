import Foundation
import Combine

private final class LockedDriverResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<IntentResponse, Error>?

    func store(_ result: Result<IntentResponse, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<IntentResponse, Error>? {
        lock.lock()
        let current = result
        lock.unlock()
        return current
    }
}

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
        let typedIntent = intent.asIntent(additionalMetadata: [
            "surface": surface.rawValue,
            "plannerSource": plannerDecision.source.rawValue,
            "plannerFamily": plannerDecision.plannerFamily.rawValue,
            "semanticQuery": plannerDecision.semanticQuery?.text ?? "",
        ])

        let box = LockedDriverResponseBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            do {
                let response = try await api.submitIntent(typedIntent)
                box.store(.success(response))
            } catch {
                box.store(.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()
        switch box.load() {
        case .success(let response):
            return ToolResult(
                success: response.outcome == .success || response.outcome == .skipped,
                data: ["summary": response.summary, "cycleID": response.cycleID.uuidString],
                error: response.outcome == .failed ? response.summary : nil
            )
        case .failure(let error):
            return ToolResult(success: false, error: error.localizedDescription)
        case .none:
            return ToolResult(success: false, error: "IntentAPI submission finished without a response")
        }
    }
}
