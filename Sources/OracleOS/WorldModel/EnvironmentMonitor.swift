import Foundation

public struct EnvironmentMonitor: Sendable {
    public init() {}

    public func detectChanges(between latest: WorldState, and expected: ExpectationModel) -> StateDelta? {
        var changedElements: [String] = []

        if let expectedApp = expected.expectedApp,
           let actualApp = latest.observation.app,
           actualApp != expectedApp {
            changedElements.append("app:\(actualApp)")
        }

        let elementLabels = Set(latest.observation.elements.compactMap { $0.label })
        for expectedElement in expected.expectedElements {
            if !elementLabels.contains(expectedElement) {
                changedElements.append("missing:\(expectedElement)")
            }
        }

        guard !changedElements.isEmpty else { return nil }
        return StateDelta(
            previousStateHash: latest.observationHash,
            currentStateHash: latest.observationHash,
            changedElements: changedElements
        )
    }
}
