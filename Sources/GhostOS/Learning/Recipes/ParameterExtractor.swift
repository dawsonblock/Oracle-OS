import Foundation

public struct ParameterExtractor {

    public static func extract(
        steps: [RecipeStep]
    ) -> ([RecipeStep], [String]) {

        var params: Set<String> = []
        var updatedSteps: [RecipeStep] = []

        for step in steps {
            if step.action.contains("\"") {
                let pName = "param_\(params.count)"
                params.insert(pName)
                
                // Parameterize the quoted text
                let updatedAction = step.action.replacingOccurrences(of: "\".*?\"", with: "{{\(pName)}}", options: .regularExpression)

                let newStep = RecipeStep(
                    id: step.id,
                    action: updatedAction,
                    target: step.target,
                    params: [pName: ""],
                    waitAfter: step.waitAfter,
                    note: step.note,
                    onFailure: step.onFailure
                )
                updatedSteps.append(newStep)
            } else {
                updatedSteps.append(step)
            }
        }

        return (updatedSteps, Array(params))
    }
}
