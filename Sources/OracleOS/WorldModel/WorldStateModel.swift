import Foundation

/// A persistent internal model of the agent's environment that is updated
/// incrementally rather than rebuilt from scratch each loop iteration.
///
/// The world model sits between perception and planning:
///
///     perception → world model update → planning → execution
///
/// By maintaining a stable representation the planner reasons over richer
/// context and can simulate future states before committing to actions.
public final class WorldStateModel: @unchecked Sendable {
    private let lock = NSLock()
    private var current: WorldModelSnapshot
    private var history: [WorldModelSnapshot] = []
    private let maxHistory: Int

    public init(maxHistory: Int = 20) {
        self.current = WorldModelSnapshot()
        self.maxHistory = maxHistory
    }

    /// The most recent consolidated snapshot of the world.
    public var snapshot: WorldModelSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Apply a diff produced by ``StateDiffEngine`` to advance the model.
    public func apply(diff: StateDiff) {
        lock.lock()
        defer { lock.unlock() }
        history.append(current)
        if history.count > maxHistory {
            history.removeFirst()
        }
        current = StateUpdater.apply(diff: diff, to: current)
    }

    /// Replace the model entirely from a fresh ``WorldState`` observation.
    public func reset(from worldState: WorldState) {
        lock.lock()
        defer { lock.unlock() }
        history.append(current)
        if history.count > maxHistory {
            history.removeFirst()
        }
        current = WorldModelSnapshot(from: worldState)
    }

    /// Returns the N most recent snapshots in chronological order (oldest first).
    public func recentHistory(limit: Int = 5) -> [WorldModelSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return Array(history.suffix(limit))
    }
}

/// An immutable snapshot of the world model at a point in time.
public struct WorldModelSnapshot: Sendable {
    public let timestamp: Date
    public let activeApplication: String?
    public let windowTitle: String?
    public let url: String?
    public let visibleElementCount: Int
    public let modalPresent: Bool
    public let repositoryRoot: String?
    public let activeBranch: String?
    public let isGitDirty: Bool
    public let openFileCount: Int
    public let buildSucceeded: Bool?
    public let failingTestCount: Int?
    public let planningStateID: String?
    public let observationHash: String?
    public let processNames: [String]
    public let knowledgeSignals: [String]
    public let notes: [String]

    public init(
        timestamp: Date = Date(),
        activeApplication: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        visibleElementCount: Int = 0,
        modalPresent: Bool = false,
        repositoryRoot: String? = nil,
        activeBranch: String? = nil,
        isGitDirty: Bool = false,
        openFileCount: Int = 0,
        buildSucceeded: Bool? = nil,
        failingTestCount: Int? = nil,
        planningStateID: String? = nil,
        observationHash: String? = nil,
        processNames: [String] = [],
        knowledgeSignals: [String] = [],
        notes: [String] = []
    ) {
        self.timestamp = timestamp
        self.activeApplication = activeApplication
        self.windowTitle = windowTitle
        self.url = url
        self.visibleElementCount = visibleElementCount
        self.modalPresent = modalPresent
        self.repositoryRoot = repositoryRoot
        self.activeBranch = activeBranch
        self.isGitDirty = isGitDirty
        self.openFileCount = openFileCount
        self.buildSucceeded = buildSucceeded
        self.failingTestCount = failingTestCount
        self.planningStateID = planningStateID
        self.observationHash = observationHash
        self.processNames = processNames
        self.knowledgeSignals = knowledgeSignals
        self.notes = notes
    }

    public init(from worldState: WorldState) {
        self.init(
            activeApplication: worldState.observation.app,
            windowTitle: worldState.observation.windowTitle,
            url: worldState.observation.url,
            visibleElementCount: worldState.observation.elements.count,
            modalPresent: worldState.planningState.modalClass != nil,
            repositoryRoot: worldState.repositorySnapshot?.workspaceRoot,
            activeBranch: worldState.repositorySnapshot?.activeBranch,
            isGitDirty: worldState.repositorySnapshot?.isGitDirty ?? false,
            openFileCount: worldState.repositorySnapshot?.files.count ?? 0,
            planningStateID: worldState.planningState.id.rawValue,
            observationHash: worldState.observationHash
        )
    }
}
