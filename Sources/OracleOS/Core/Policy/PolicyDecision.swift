import Foundation

public struct PolicyDecision: Codable, Sendable {
    public let allowed: Bool
    public let riskLevel: RiskLevel
    public let requiresApproval: Bool
    public let reason: String?

    public init(
        allowed: Bool,
        riskLevel: RiskLevel,
        requiresApproval: Bool = false,
        reason: String? = nil
    ) {
        self.allowed = allowed
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
        self.reason = reason
    }
}
