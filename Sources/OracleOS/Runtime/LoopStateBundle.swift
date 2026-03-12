import Foundation

public struct LoopStateBundle: Sendable {
    public let taskContext: TaskContext
    public let observation: Observation
    public let worldState: WorldState
    public let repositorySnapshot: RepositorySnapshot?
    public let hostSnapshot: HostSnapshot?
    public let browserSession: BrowserSession?
    public let memoryContext: MemoryQueryContext

    public init(
        taskContext: TaskContext,
        observation: Observation,
        worldState: WorldState,
        repositorySnapshot: RepositorySnapshot?,
        hostSnapshot: HostSnapshot?,
        browserSession: BrowserSession?,
        memoryContext: MemoryQueryContext
    ) {
        self.taskContext = taskContext
        self.observation = observation
        self.worldState = worldState
        self.repositorySnapshot = repositorySnapshot
        self.hostSnapshot = hostSnapshot
        self.browserSession = browserSession
        self.memoryContext = memoryContext
    }
}
