public struct FailureAnalyzer {

    public static func classify(
        intent: ActionIntent,
        result: ActionResult,
        before: Observation,
        after: Observation
    ) -> FailureClass? {

        if result.success == false {

            if intent.elementID != nil &&
               !after.elements.contains(where: { $0.id == intent.elementID }) {

                return .elementNotFound
            }

            if before.app != after.app {

                return .wrongFocus
            }

            return .actionFailed
        }

        return nil
    }
}
