import Foundation

public final class ReadFileSkill: Skill {
    public let name = "read_file"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore _: AppMemoryStore
    ) throws -> SkillResolution {
        let intent = ActionIntent(
            agentKind: .os,
            app: state.observation.app ?? "Finder",
            name: "read file \(query.text ?? "")",
            action: "read-file",
            query: query.text
        )
        return SkillResolution(intent: intent, semanticQuery: query)
    }
}
