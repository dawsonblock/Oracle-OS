import Foundation

public struct ClickSkill: Skill {

    public let name = "click"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore: AppMemoryStore
    ) throws -> SkillResolution {
        let best: ElementCandidate

        do {
            best = try state.resolve(
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

        let intent = ActionIntent.click(
            app: state.observation.app,
            query: best.element.label ?? query.text,
            role: best.element.role,
            domID: best.element.id
        )

        return SkillResolution(
            intent: intent,
            selectedCandidate: best,
            semanticQuery: query
        )
    }
}
