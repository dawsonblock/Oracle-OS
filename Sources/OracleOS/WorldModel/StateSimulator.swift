import Foundation

/// Simulates the predicted effect of an action on the current world model
/// snapshot without actually executing it. Used by the planner to evaluate
/// candidate plans before committing.
public final class StateSimulator: @unchecked Sendable {

    public init() {}

    /// Predict what the world model would look like after executing an operator.
    public func predict(
        from snapshot: WorldModelSnapshot,
        operator op: Operator,
        state: ReasoningPlanningState
    ) -> StateSimulationResult {
        var predicted = snapshot
        var changes: [String] = []
        var confidence: Double = 0.5

        switch op.kind {
        case .dismissModal:
            if snapshot.modalPresent {
                predicted = withModalDismissed(snapshot)
                changes.append("modal dismissed")
                confidence = 0.85
            } else {
                changes.append("no modal to dismiss")
                confidence = 0.1
            }

        case .focusWindow, .openApplication:
            let targetApp = state.targetApplication ?? "unknown"
            predicted = withApplicationChanged(snapshot, to: targetApp)
            changes.append("focused \(targetApp)")
            confidence = 0.75

        case .runTests:
            changes.append("tests executed")
            confidence = 0.6

        case .applyPatch:
            predicted = withGitDirty(snapshot)
            changes.append("patch applied, repo dirty")
            confidence = 0.65

        case .buildProject:
            changes.append("build executed")
            confidence = 0.6

        case .rollbackPatch, .revertPatch:
            predicted = withPatchReverted(snapshot)
            changes.append("patch reverted")
            confidence = 0.8

        default:
            changes.append("action executed: \(op.kind.rawValue)")
            confidence = 0.4
        }

        return StateSimulationResult(
            predictedSnapshot: predicted,
            changes: changes,
            confidence: confidence
        )
    }

    private func withModalDismissed(_ s: WorldModelSnapshot) -> WorldModelSnapshot {
        WorldModelSnapshot(
            timestamp: Date(),
            activeApplication: s.activeApplication,
            windowTitle: s.windowTitle,
            url: s.url,
            visibleElementCount: s.visibleElementCount,
            modalPresent: false,
            repositoryRoot: s.repositoryRoot,
            activeBranch: s.activeBranch,
            isGitDirty: s.isGitDirty,
            openFileCount: s.openFileCount,
            buildSucceeded: s.buildSucceeded,
            failingTestCount: s.failingTestCount,
            planningStateID: s.planningStateID,
            observationHash: s.observationHash,
            processNames: s.processNames,
            knowledgeSignals: s.knowledgeSignals,
            notes: s.notes
        )
    }

    private func withApplicationChanged(_ s: WorldModelSnapshot, to app: String) -> WorldModelSnapshot {
        WorldModelSnapshot(
            timestamp: Date(),
            activeApplication: app,
            windowTitle: s.windowTitle,
            url: s.url,
            visibleElementCount: s.visibleElementCount,
            modalPresent: s.modalPresent,
            repositoryRoot: s.repositoryRoot,
            activeBranch: s.activeBranch,
            isGitDirty: s.isGitDirty,
            openFileCount: s.openFileCount,
            buildSucceeded: s.buildSucceeded,
            failingTestCount: s.failingTestCount,
            planningStateID: s.planningStateID,
            observationHash: s.observationHash,
            processNames: s.processNames,
            knowledgeSignals: s.knowledgeSignals,
            notes: s.notes
        )
    }

    private func withGitDirty(_ s: WorldModelSnapshot) -> WorldModelSnapshot {
        WorldModelSnapshot(
            timestamp: Date(),
            activeApplication: s.activeApplication,
            windowTitle: s.windowTitle,
            url: s.url,
            visibleElementCount: s.visibleElementCount,
            modalPresent: s.modalPresent,
            repositoryRoot: s.repositoryRoot,
            activeBranch: s.activeBranch,
            isGitDirty: true,
            openFileCount: s.openFileCount,
            buildSucceeded: s.buildSucceeded,
            failingTestCount: s.failingTestCount,
            planningStateID: s.planningStateID,
            observationHash: s.observationHash,
            processNames: s.processNames,
            knowledgeSignals: s.knowledgeSignals,
            notes: s.notes
        )
    }

    private func withPatchReverted(_ s: WorldModelSnapshot) -> WorldModelSnapshot {
        WorldModelSnapshot(
            timestamp: Date(),
            activeApplication: s.activeApplication,
            windowTitle: s.windowTitle,
            url: s.url,
            visibleElementCount: s.visibleElementCount,
            modalPresent: s.modalPresent,
            repositoryRoot: s.repositoryRoot,
            activeBranch: s.activeBranch,
            isGitDirty: false,
            openFileCount: s.openFileCount,
            buildSucceeded: s.buildSucceeded,
            failingTestCount: s.failingTestCount,
            planningStateID: s.planningStateID,
            observationHash: s.observationHash,
            processNames: s.processNames,
            knowledgeSignals: s.knowledgeSignals,
            notes: s.notes
        )
    }
}

/// The result of simulating a single operator's effect on the world model.
public struct StateSimulationResult: Sendable {
    public let predictedSnapshot: WorldModelSnapshot
    public let changes: [String]
    public let confidence: Double

    public init(
        predictedSnapshot: WorldModelSnapshot,
        changes: [String] = [],
        confidence: Double = 0.5
    ) {
        self.predictedSnapshot = predictedSnapshot
        self.changes = changes
        self.confidence = confidence
    }
}
