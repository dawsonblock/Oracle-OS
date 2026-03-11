import AXorcist
import Foundation

public struct RecipeInducer {

    @MainActor
    public static func induce(
        name: String,
        trace: [TraceEvent],
        observation: Observation
    ) -> Recipe {

        let segments = TraceSegmenter.segment(events: trace)

        var steps: [RecipeStep] = []

        for (index, event) in segments.enumerated() {
            let target: Locator?
            if let selectedElementID = event.selectedElementID {
                target = LocatorBuilder.build(domId: selectedElementID)
            } else if let actionTarget = event.actionTarget {
                target = LocatorBuilder.build(query: actionTarget)
            } else {
                target = nil
            }

            let step =
                RecipeStep(
                    id: index,
                    action: event.actionName,
                    target: target,
                    params: nil,
                    waitAfter: nil,
                    note: nil,
                    onFailure: nil
                )

            steps.append(step)
        }

        let (paramSteps, params) =
            ParameterExtractor.extract(steps: steps)

        var recipeParams: [String: RecipeParam] = [:]
        for param in params {
            recipeParams[param] = RecipeParam(type: "string", description: "extracted parameter", required: true)
        }

        return Recipe(
            schemaVersion: 2,
            name: name,
            description: "Induced from trace",
            app: observation.app ?? "unknown",
            params: recipeParams.isEmpty ? nil : recipeParams,
            preconditions: nil,
            steps: paramSteps,
            onFailure: nil
        )
    }
}
