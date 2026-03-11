import Foundation

public final class OpenAppSkill: Skill {
    public let name = "open_app"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state _: WorldState,
        memoryStore _: AppMemoryStore
    ) throws -> SkillResolution {
        let appName = query.app ?? query.text ?? "Finder"
        return SkillResolution(intent: .focus(app: appName), semanticQuery: query)
    }
}
