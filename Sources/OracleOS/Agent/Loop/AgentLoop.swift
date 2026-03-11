import Foundation

@MainActor
public final class AgentLoop {
    private let observationProvider: (any ObservationProvider)?
    private let executionDriver: (any AgentExecutionDriver)?
    private let stateAbstraction: StateAbstraction
    private let planner: Planner
    private let graphStore: GraphStore

    public init(
        observationProvider: (any ObservationProvider)? = nil,
        executionDriver: (any AgentExecutionDriver)? = nil,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        planner: Planner = Planner(),
        graphStore: GraphStore = GraphStore()
    ) {
        self.observationProvider = observationProvider
        self.executionDriver = executionDriver
        self.stateAbstraction = stateAbstraction
        self.planner = planner
        self.graphStore = graphStore
    }

    @discardableResult
    public func run(goal: Goal, maxSteps: Int = 25) -> WorldState? {
        guard let observationProvider, let executionDriver else {
            return nil
        }

        planner.setGoal(goal)

        var latestWorldState: WorldState?

        for _ in 0..<maxSteps {
            let observation = observationProvider.observe()
            let observationHash = ObservationHash.hash(observation)
            let planningState = stateAbstraction.abstract(
                observation: observation,
                observationHash: observationHash
            )
            let worldState = WorldState(
                observationHash: observationHash,
                planningState: planningState,
                observation: observation
            )
            latestWorldState = worldState

            if planner.goalReached(state: planningState) {
                return worldState
            }

            guard let actionContract = planner.nextAction(
                worldState: worldState,
                graphStore: graphStore
            ) else {
                return worldState
            }

            _ = executionDriver.execute(actionContract)
        }

        return latestWorldState
    }

    public func run(goal: String, state: WorldState) async {
        let interpretedGoal = planner.interpretGoal(goal)
        planner.setGoal(interpretedGoal)
        _ = planner.nextAction(worldState: state, graphStore: graphStore)
    }
}
