import Foundation

public final class TypeSkill: Skill {
    public let name = "type"

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
        let intent = ActionIntent.type(
            app: state.observation.app,
            into: candidate.element.label ?? query.text,
            domID: candidate.element.id,
            text: query.text ?? ""
        )
        return SkillResolution(intent: intent, selectedCandidate: candidate, semanticQuery: query)
    }
}
