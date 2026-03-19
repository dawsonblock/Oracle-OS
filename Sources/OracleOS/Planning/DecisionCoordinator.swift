import Foundation

@MainActor
extension DecisionCoordinator {
    /// Canonical planning boundary: intent in, command out.
    /// Planning must terminate at Command and never execute.
    public func decide(_ intent: Intent) async -> Command {
        let context = PlannerContext(state: WorldStateModel())
        do {
            return try await planner.plan(intent: intent, context: context)
        } catch {
            return Command(
                type: .system,
                payload: .ui(UIAction(name: "focus", app: intent.metadata["app"])),
                metadata: CommandMetadata(
                    intentID: intent.id,
                    source: "decision.fallback",
                    traceTags: ["planning-failed", String(describing: error)]
                )
            )
        }
    }
}
