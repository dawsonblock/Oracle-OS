import Foundation

@MainActor
public final class StateCoordinator {
    private let observationProvider: any ObservationProvider
    private let stateAbstraction: StateAbstraction
    private let repositoryIndexer: RepositoryIndexer
    private let automationHost: AutomationHost
    private let browserPageStateBuilder: BrowserPageStateBuilder

    public init(
        observationProvider: any ObservationProvider,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        automationHost: AutomationHost = .live(),
        browserPageStateBuilder: BrowserPageStateBuilder = BrowserPageStateBuilder()
    ) {
        self.observationProvider = observationProvider
        self.stateAbstraction = stateAbstraction
        self.repositoryIndexer = repositoryIndexer
        self.automationHost = automationHost
        self.browserPageStateBuilder = browserPageStateBuilder
    }

    public func buildState(
        taskContext: TaskContext,
        lastAction: ActionIntent?
    ) -> LoopStateBundle {
        let observation = observationProvider.observe()
        let repositorySnapshot = repositorySnapshot(for: taskContext)
        let worldState = WorldState(
            observation: observation,
            lastAction: lastAction,
            repositorySnapshot: repositorySnapshot,
            stateAbstraction: stateAbstraction
        )
        let memoryContext = MemoryQueryContext(taskContext: taskContext, worldState: worldState)
        return LoopStateBundle(
            taskContext: taskContext,
            observation: observation,
            worldState: worldState,
            repositorySnapshot: repositorySnapshot,
            hostSnapshot: automationHost.snapshots.captureSnapshot(appName: observation.app),
            browserSession: browserPageStateBuilder.build(from: observation),
            memoryContext: memoryContext
        )
    }

    private func repositorySnapshot(for taskContext: TaskContext) -> RepositorySnapshot? {
        guard taskContext.agentKind == .code || taskContext.agentKind == .mixed,
              let workspaceRoot = taskContext.workspaceRoot
        else {
            return nil
        }
        return repositoryIndexer.indexIfNeeded(
            workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        )
    }
}
