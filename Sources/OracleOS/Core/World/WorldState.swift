public struct WorldState {

    public var observation: Observation

    public var lastAction: ActionIntent?

    public init(observation: Observation) {
        self.observation = observation
    }
}
