import Foundation

public struct RecipeValidator {

    public static func validate(
        recipe: Recipe,
        state: WorldState
    ) -> Bool {

        guard recipe.steps.count > 0 else {
            return false
        }

        for step in recipe.steps {

            if step.action.isEmpty {
                return false
            }
        }

        return true
    }
}
