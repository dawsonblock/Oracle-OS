public protocol Skill {

    var name: String { get }

    func execute(
        state: WorldState
    ) async throws -> ActionResult
}
