import Foundation

/// Applies a ``StateDiff`` to a ``WorldModelSnapshot`` to produce an updated snapshot.
public enum StateUpdater {

    public static func apply(
        diff: StateDiff,
        to snapshot: WorldModelSnapshot
    ) -> WorldModelSnapshot {
        let ws = diff.incomingWorldState
        var notes = snapshot.notes

        for change in diff.changes {
            switch change {
            case let .applicationChanged(from, to):
                notes.append("app: \(from ?? "nil") → \(to ?? "nil")")
            case let .modalStateChanged(present):
                notes.append("modal: \(present ? "appeared" : "dismissed")")
            case let .branchChanged(from, to):
                notes.append("branch: \(from ?? "nil") → \(to ?? "nil")")
            default:
                break
            }
        }

        // Keep only the most recent notes to prevent unbounded growth.
        let trimmedNotes = Array(notes.suffix(20))

        return WorldModelSnapshot(
            timestamp: diff.timestamp,
            activeApplication: ws.observation.app,
            windowTitle: ws.observation.windowTitle,
            url: ws.observation.url,
            visibleElementCount: ws.observation.elements.count,
            modalPresent: ws.planningState.modalClass != nil,
            repositoryRoot: ws.repositorySnapshot?.workspaceRoot ?? snapshot.repositoryRoot,
            activeBranch: ws.repositorySnapshot?.activeBranch ?? snapshot.activeBranch,
            isGitDirty: ws.repositorySnapshot?.isGitDirty ?? snapshot.isGitDirty,
            openFileCount: ws.repositorySnapshot?.files.count ?? snapshot.openFileCount,
            buildSucceeded: snapshot.buildSucceeded,
            failingTestCount: snapshot.failingTestCount,
            planningStateID: ws.planningState.id.rawValue,
            observationHash: ws.observationHash,
            processNames: snapshot.processNames,
            knowledgeSignals: snapshot.knowledgeSignals,
            notes: trimmedNotes
        )
    }
}
