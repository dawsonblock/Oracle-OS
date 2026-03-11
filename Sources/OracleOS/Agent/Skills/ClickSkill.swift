public struct ClickSkill: Skill {

    public let name = "click"

    public func execute(
        state: WorldState
    ) async throws -> ActionResult {

        guard let element = state.observation.elements.first else {
            return ActionResult(success: false, message: "No element")
        }

        return ActionResult(success: true, message: "Clicked \(element.id)")
    }
}
