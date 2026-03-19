import Foundation

@MainActor
extension AgentLoop {
    public func run() async {
        while running {
            await tick()
        }
    }

    private func tick() async {
        guard let intent = await intake.next() else {
            await Task.yield()
            return
        }

        _ = try? await orchestrator.submitIntent(intent)
    }
}
