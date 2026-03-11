import Foundation

public struct ActionContract: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let skillName: String
    public let targetRole: String?
    public let targetLabel: String?
    public let locatorStrategy: String

    public init(
        id: String,
        skillName: String,
        targetRole: String?,
        targetLabel: String?,
        locatorStrategy: String
    ) {
        self.id = id
        self.skillName = skillName
        self.targetRole = targetRole
        self.targetLabel = targetLabel
        self.locatorStrategy = locatorStrategy
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "skill_name": skillName,
            "locator_strategy": locatorStrategy,
        ]
        if let targetRole {
            result["target_role"] = targetRole
        }
        if let targetLabel {
            result["target_label"] = targetLabel
        }
        return result
    }

    public static func from(
        intent: ActionIntent,
        method: String?,
        selectedElementLabel: String?
    ) -> ActionContract {
        let locatorStrategy = method ?? inferredLocatorStrategy(for: intent)
        let targetLabel = selectedElementLabel ?? intent.targetQuery ?? intent.elementID
        let contractID = [
            intent.action,
            intent.role ?? "none",
            targetLabel ?? "none",
            locatorStrategy,
        ].joined(separator: "|")

        return ActionContract(
            id: contractID,
            skillName: intent.action,
            targetRole: intent.role,
            targetLabel: targetLabel,
            locatorStrategy: locatorStrategy
        )
    }

    private static func inferredLocatorStrategy(for intent: ActionIntent) -> String {
        if intent.x != nil || intent.y != nil {
            return "coordinates"
        }
        if intent.domID != nil {
            return "dom-id"
        }
        if intent.query != nil {
            return "query"
        }
        return "direct"
    }
}
