import Foundation

public struct StateEstimator: Sendable {
    public init() {}
    
    public func estimate(from observation: Observation) -> WorldState {
        fatalError("State estimation logic not yet implemented")
    }
}
