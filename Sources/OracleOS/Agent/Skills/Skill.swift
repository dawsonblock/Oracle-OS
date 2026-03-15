import Foundation

public enum SkillResolutionError: Error, Sendable, Equatable {
    case noCandidate(String)
    case ambiguousTarget(String, Double)

    public var failureClass: FailureClass {
        switch self {
        case .noCandidate:
            return .elementNotFound
        case .ambiguousTarget:
            return .elementAmbiguous
        }
    }
}

public struct SkillResolution: Sendable {
    public let intent: ActionIntent
    public let selectedCandidate: ElementCandidate?
    public let semanticQuery: ElementQuery?
    public let repositorySnapshotID: String?

    public init(
        intent: ActionIntent,
        selectedCandidate: ElementCandidate? = nil,
        semanticQuery: ElementQuery? = nil,
        repositorySnapshotID: String? = nil
    ) {
        self.intent = intent
        self.selectedCandidate = selectedCandidate
        self.semanticQuery = semanticQuery
        self.repositorySnapshotID = repositorySnapshotID
    }
}

public protocol Skill {

    var name: String { get }

    func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore: UnifiedMemoryStore
    ) throws -> SkillResolution
}

public protocol CodeSkill {
    var name: String { get }

    func resolve(
        taskContext: TaskContext,
        state: WorldState,
        memoryStore: UnifiedMemoryStore
    ) throws -> SkillResolution
}
