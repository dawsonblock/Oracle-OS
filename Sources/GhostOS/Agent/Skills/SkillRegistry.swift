public final class SkillRegistry {

    private var skills: [String: Skill] = [:]

    public func register(_ skill: Skill) {
        skills[skill.name] = skill
    }

    public func get(_ name: String) -> Skill? {
        skills[name]
    }
}
