public struct WorldState {
    public var observationHash: String
    public var planningState: PlanningState
    public var beliefStateID: String?

    public var observation: Observation

    public var lastAction: ActionIntent?

    public init(
        observation: Observation,
        lastAction: ActionIntent? = nil,
        beliefStateID: String? = nil,
        stateAbstraction: StateAbstraction = StateAbstraction()
    ) {
        let observationHash = ObservationHash.hash(observation)
        self.observationHash = observationHash
        self.planningState = stateAbstraction.abstract(
            observation: observation,
            observationHash: observationHash
        )
        self.beliefStateID = beliefStateID
        self.observation = observation
        self.lastAction = lastAction
    }

    public init(
        observationHash: String,
        planningState: PlanningState,
        beliefStateID: String? = nil,
        observation: Observation,
        lastAction: ActionIntent? = nil
    ) {
        self.observationHash = observationHash
        self.planningState = planningState
        self.beliefStateID = beliefStateID
        self.observation = observation
        self.lastAction = lastAction
    }
}
