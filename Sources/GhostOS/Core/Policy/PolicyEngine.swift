import Foundation

public final class PolicyEngine: @unchecked Sendable {
    public static let shared = PolicyEngine()

    public var mode: PolicyMode

    public init(mode: PolicyMode? = nil) {
        self.mode = mode ?? Self.defaultMode()
    }

    public func evaluate(intent: ActionIntent) -> PolicyDecision {
        let risk = riskLevel(for: intent)

        switch mode {
        case .open:
            return PolicyDecision(allowed: true, riskLevel: risk)

        case .confirmRisky:
            if risk == .risky {
                return PolicyDecision(
                    allowed: false,
                    riskLevel: risk,
                    requiresApproval: true,
                    reason: "Action requires approval in confirm-risky mode"
                )
            }
            if risk == .blocked {
                return PolicyDecision(allowed: false, riskLevel: risk, reason: "Action blocked by policy")
            }
            return PolicyDecision(allowed: true, riskLevel: risk)

        case .lockedDown:
            if risk == .low {
                return PolicyDecision(allowed: true, riskLevel: risk)
            }
            return PolicyDecision(allowed: false, riskLevel: risk, reason: "Action blocked by locked-down policy")
        }
    }

    private func riskLevel(for intent: ActionIntent) -> RiskLevel {
        let target = [intent.targetQuery, intent.domID, intent.text].compactMap { $0?.lowercased() }.joined(separator: " ")
        if target.contains("password") {
            return .blocked
        }
        if ["send", "submit", "purchase", "delete", "trash", "remove"].contains(where: { target.contains($0) }) {
            return .risky
        }
        return .low
    }

    private static func defaultMode() -> PolicyMode {
        guard let raw = ProcessInfo.processInfo.environment["GHOST_OS_POLICY_MODE"] else {
            return .confirmRisky
        }
        return PolicyMode(rawValue: raw) ?? .confirmRisky
    }
}
