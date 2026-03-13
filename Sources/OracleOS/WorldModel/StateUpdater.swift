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
        let repo = ws.repositorySnapshot

        return snapshot.copy(
            activeApplication: .some(ws.observation.app),
            windowTitle: .some(ws.observation.windowTitle),
            url: .some(ws.observation.url),
            visibleElementCount: ws.observation.elements.count,
            modalPresent: ws.planningState.modalClass != nil,
            repositoryRoot: .some(repo?.workspaceRoot ?? snapshot.repositoryRoot),
            activeBranch: .some(repo?.activeBranch ?? snapshot.activeBranch),
            isGitDirty: repo?.isGitDirty ?? snapshot.isGitDirty,
            openFileCount: repo?.files.count ?? snapshot.openFileCount,
            planningStateID: .some(ws.planningState.id.rawValue),
            observationHash: .some(ws.observationHash),
            notes: trimmedNotes
        )
    }
}
