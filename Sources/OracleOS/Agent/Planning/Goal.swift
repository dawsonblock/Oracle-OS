import Foundation

public struct Goal: Codable, Sendable, Equatable {
    public let description: String
    public let targetApp: String?
    public let targetDomain: String?
    public let targetTaskPhase: String?
    public let workspaceRoot: String?
    public let preferredAgentKind: AgentKind?
    public let experimentCandidates: [CandidatePatch]?

    public init(
        description: String,
        targetApp: String? = nil,
        targetDomain: String? = nil,
        targetTaskPhase: String? = nil,
        workspaceRoot: String? = nil,
        preferredAgentKind: AgentKind? = nil,
        experimentCandidates: [CandidatePatch]? = nil
    ) {
        self.description = description
        self.targetApp = targetApp
        self.targetDomain = targetDomain
        self.targetTaskPhase = targetTaskPhase
        self.workspaceRoot = workspaceRoot
        self.preferredAgentKind = preferredAgentKind
        self.experimentCandidates = experimentCandidates
    }
}
