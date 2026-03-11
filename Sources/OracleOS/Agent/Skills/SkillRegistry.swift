public final class SkillRegistry {

    private var skills: [String: any Skill] = [:]

    public func register(_ skill: any Skill) {
        skills[skill.name] = skill
    }

    public func get(_ name: String) -> (any Skill)? {
        skills[name]
    }
}
