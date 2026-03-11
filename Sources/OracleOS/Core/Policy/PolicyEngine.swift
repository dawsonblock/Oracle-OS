import Foundation

public final class PolicyEngine: @unchecked Sendable {
    public static let shared = PolicyEngine()

    public var mode: PolicyMode

    public init(mode: PolicyMode? = nil) {
        self.mode = mode ?? Self.defaultMode()
    }

    public func evaluate(intent: ActionIntent) -> PolicyDecision {
        evaluate(
            intent: intent,
            context: PolicyEvaluationContext(surface: .mcp, toolName: nil, appName: intent.app)
        )
    }

    public func evaluate(intent: ActionIntent, context: PolicyEvaluationContext) -> PolicyDecision {
        let appProtectionProfile = PolicyRules.appProtectionProfile(for: context.appName ?? intent.app)
        let protectedOperation = PolicyRules.protectedOperation(
            for: intent,
            context: context,
            appProtectionProfile: appProtectionProfile
        )
        let riskLevel: RiskLevel = switch protectedOperation {
        case .credentialEntry, .settingsChange, .terminalControl, .clipboardExfiltration:
            .blocked
        case .send, .purchase, .delete, .uploadShare:
            .risky
        case nil:
            .low
        }

        let baseDecision = PolicyDecision(
            allowed: riskLevel == .low,
            riskLevel: riskLevel,
            protectedOperation: protectedOperation,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: riskLevel == .blocked,
            surface: context.surface,
            policyMode: mode,
            requiresApproval: riskLevel == .risky,
            reason: defaultReason(for: riskLevel, protectedOperation: protectedOperation, mode: mode)
        )

        switch mode {
        case .open:
            if riskLevel == .blocked {
                return baseDecision.withReason(baseDecision.reason ?? "Action blocked by policy")
            }
            return PolicyDecision(
                allowed: true,
                riskLevel: riskLevel,
                protectedOperation: protectedOperation,
                appProtectionProfile: appProtectionProfile,
                blockedByPolicy: false,
                surface: context.surface,
                policyMode: mode,
                requiresApproval: false,
                reason: baseDecision.reason
            )

        case .confirmRisky:
            return baseDecision

        case .lockedDown:
            if riskLevel == .low {
                return PolicyDecision(
                    allowed: true,
                    riskLevel: riskLevel,
                    protectedOperation: protectedOperation,
                    appProtectionProfile: appProtectionProfile,
                    blockedByPolicy: false,
                    surface: context.surface,
                    policyMode: mode,
                    requiresApproval: false,
                    reason: nil
                )
            }
            return PolicyDecision(
                allowed: false,
                riskLevel: riskLevel,
                protectedOperation: protectedOperation,
                appProtectionProfile: appProtectionProfile,
                blockedByPolicy: true,
                surface: context.surface,
                policyMode: mode,
                requiresApproval: false,
                reason: "Action blocked by locked-down policy"
            )
        }
    }

    public static func defaultMode() -> PolicyMode {
        guard let raw = ProcessInfo.processInfo.environment["GHOST_OS_POLICY_MODE"] else {
            return .confirmRisky
        }
        return PolicyMode(rawValue: raw) ?? .confirmRisky
    }

    private func defaultReason(
        for riskLevel: RiskLevel,
        protectedOperation: ProtectedOperation?,
        mode: PolicyMode
    ) -> String? {
        switch riskLevel {
        case .low:
            return nil
        case .risky:
            return "Action requires approval in \(mode.rawValue) mode"
        case .blocked:
            if let protectedOperation {
                return "Action blocked by policy: \(protectedOperation.rawValue)"
            }
            return "Action blocked by policy"
        }
    }
}
