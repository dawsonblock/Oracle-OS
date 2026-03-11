public struct WorldReducer {

    public static func update(
        state: WorldState,
        newObservation: Observation
    ) -> WorldState {

        var new = state
        new.observation = newObservation
        return new
    }
}
