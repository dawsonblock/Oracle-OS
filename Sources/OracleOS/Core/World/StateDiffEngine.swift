import Foundation

/// Computes the difference between two world states so the ``WorldStateModel``
/// can be updated incrementally instead of replaced wholesale.
public enum StateDiffEngine {

    /// Compute a diff between the current model snapshot and a new observation.
    public static func diff(
        current: WorldModelSnapshot,
        incoming: WorldState
    ) -> StateDiff {
        var changes: [StateDiff.Change] = []

        if current.activeApplication != incoming.observation.app {
            changes.append(.applicationChanged(
                from: current.activeApplication,
                to: incoming.observation.app
            ))
        }

        if current.windowTitle != incoming.observation.windowTitle {
            changes.append(.windowTitleChanged(
                from: current.windowTitle,
                to: incoming.observation.windowTitle
            ))
        }

        if current.url != incoming.observation.url {
            changes.append(.urlChanged(
                from: current.url,
                to: incoming.observation.url
            ))
        }

        let incomingModalPresent = incoming.planningState.modalClass != nil
        if current.modalPresent != incomingModalPresent {
            changes.append(.modalStateChanged(present: incomingModalPresent))
        }

        let incomingElementCount = incoming.observation.elements.count
        if current.visibleElementCount != incomingElementCount {
            changes.append(.elementCountChanged(
                from: current.visibleElementCount,
                to: incomingElementCount
            ))
        }

        if let repo = incoming.repositorySnapshot {
            if current.activeBranch != repo.activeBranch {
                changes.append(.branchChanged(
                    from: current.activeBranch,
                    to: repo.activeBranch
                ))
            }
            if current.isGitDirty != repo.isGitDirty {
                changes.append(.gitDirtyChanged(isDirty: repo.isGitDirty))
            }
        }

        if current.observationHash != incoming.observationHash {
            changes.append(.observationHashChanged(
                from: current.observationHash,
                to: incoming.observationHash
            ))
        }

        return StateDiff(
            changes: changes,
            incomingWorldState: incoming,
            timestamp: Date()
        )
    }
}

/// Represents the set of changes between two world model states.
public struct StateDiff: Sendable {
    public let changes: [Change]
    public let incomingWorldState: WorldState
    public let timestamp: Date

    public var isEmpty: Bool { changes.isEmpty }

    public var changeCount: Int { changes.count }

    public enum Change: Sendable {
        case applicationChanged(from: String?, to: String?)
        case windowTitleChanged(from: String?, to: String?)
        case urlChanged(from: String?, to: String?)
        case modalStateChanged(present: Bool)
        case elementCountChanged(from: Int, to: Int)
        case branchChanged(from: String?, to: String?)
        case gitDirtyChanged(isDirty: Bool)
        case observationHashChanged(from: String?, to: String?)
    }
}
