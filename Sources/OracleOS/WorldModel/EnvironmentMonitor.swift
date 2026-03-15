import Foundation

public struct EnvironmentMonitor: Sendable {
    public init() {}
    
    /// Monitors discrepancy between observed state and expected postconditions.
    /// TODO: Implement minimal change detection between `latest` and `expected` and return a `StateDelta`.
    @available(*, deprecated, message: "EnvironmentMonitor.detectChanges is not yet implemented and always returns nil. Do not rely on it for hardening.")
    public func detectChanges(between latest: WorldState, and expected: ExpectationModel) -> StateDelta? {
        return nil
    }
}
