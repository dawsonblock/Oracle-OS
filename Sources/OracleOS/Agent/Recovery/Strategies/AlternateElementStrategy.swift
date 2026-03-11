public struct AlternateElementStrategy: RecoveryStrategy {

    public let name = "alternate_element"

    public func attempt(
        failure: FailureClass,
        state: WorldState
    ) async throws -> ActionResult {

        guard let label =
            state.observation.elements.first(where: { $0.id == state.observation.focusedElementID })?.label else {

            return ActionResult(
                success: false,
                message: "No alternate element"
            )
        }

        let query =
            ElementQuery(
                text: label,
                clickable: true
            )

        let ranked =
            ElementRanker.rank(
                elements: state.observation.elements,
                query: query
            )

        if ranked.count > 1 {

            let alt = ranked[1]

            print("Using alternate:", alt.element.id)

            return ActionResult(
                success: true,
                message: "Alternate element chosen"
            )
        }

        return ActionResult(
            success: false,
            message: "No alternate candidate"
        )
    }
}
