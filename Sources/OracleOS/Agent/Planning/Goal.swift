import Foundation

public struct Goal: Codable, Sendable, Equatable {
    public let description: String
    public let targetApp: String?
    public let targetDomain: String?
    public let targetTaskPhase: String?

    public init(
        description: String,
        targetApp: String? = nil,
        targetDomain: String? = nil,
        targetTaskPhase: String? = nil
    ) {
        self.description = description
        self.targetApp = targetApp
        self.targetDomain = targetDomain
        self.targetTaskPhase = targetTaskPhase
    }
}
