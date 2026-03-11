import Foundation

public final class ReadFileSkill: Skill {
    public let name = "read_file"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore: AppMemoryStore
    ) throws -> SkillResolution {
        let candidate: ElementCandidate
        do {
            candidate = try state.resolve(
                query: query,
                memoryStore: memoryStore,
                minimumScore: 0.6,
                maximumAmbiguity: 0.2
            )
        } catch let error as WorldQueryResolutionError {
            switch error {
            case let .notFound(label):
                throw SkillResolutionError.noCandidate(label)
            case let .ambiguous(label, ambiguity):
                throw SkillResolutionError.ambiguousTarget(label, ambiguity)
            case let .lowConfidence(label, score):
                throw SkillResolutionError.ambiguousTarget(label, score)
            }
        }

        let intent = ActionIntent(
            agentKind: .os,
            app: state.observation.app ?? "Finder",
            name: "read file \(candidate.element.label ?? query.text ?? "")",
            action: "read-file",
            query: candidate.element.label ?? query.text,
            role: candidate.element.role,
            domID: candidate.element.id
        )
        return SkillResolution(
            intent: intent,
            selectedCandidate: candidate,
            semanticQuery: query
        )
    }
}
