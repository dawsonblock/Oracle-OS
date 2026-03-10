import Foundation

public struct RecipeInducer {

    public static func induce(
        name: String,
        trace: [TraceEvent],
        observation: Observation
    ) -> Recipe {

        let segments = TraceSegmenter.segment(events: trace)

        var steps: [RecipeStep] = []

        for (index, event) in segments.enumerated() {

            let step =
                RecipeStep(
                    id: index,
                    action: event.intent.action,
                    target: nil, // Future: map observation.focusedElement to a Locator
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
