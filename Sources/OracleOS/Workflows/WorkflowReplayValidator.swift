import Foundation

public struct WorkflowReplayValidator: Sendable {
    public init() {}

    public func validate(plan: WorkflowPlan, against segments: [TraceSegment]) -> Double {
        guard !segments.isEmpty else { return 0 }

        let matches = segments.filter { segment in
            segmentMatches(plan: plan, segment: segment)
        }

        return Double(matches.count) / Double(segments.count)
    }

    private func segmentMatches(plan: WorkflowPlan, segment: TraceSegment) -> Bool {
        guard segment.events.count == plan.steps.count else {
            return false
        }

        return zip(plan.steps, segment.events).allSatisfy { step, event in
            let contractID = event.actionContractID ?? event.actionName
            guard step.actionContract.id == contractID else {
                return false
            }
            guard step.agentKind.rawValue == (event.agentKind ?? step.agentKind.rawValue) else {
                return false
            }
            if let workspaceRelativePath = step.actionContract.workspaceRelativePath {
                guard workspaceRelativePath == event.workspaceRelativePath else {
                    return false
                }
            }
            return true
        }
    }
}
