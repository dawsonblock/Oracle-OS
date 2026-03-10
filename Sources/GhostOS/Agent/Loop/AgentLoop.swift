public final class AgentLoop {

    private let planner = Planner()

    public func run(goal: String, state: WorldState) async {

        let plan = planner.plan(goal: goal)

        var currentState = state

        for step in plan.steps {

            print("Executing step:", step)

            // skill lookup would happen here

            currentState.lastAction = ActionIntent(app: "unknown", name: step, action: step)
        }
    }
}
