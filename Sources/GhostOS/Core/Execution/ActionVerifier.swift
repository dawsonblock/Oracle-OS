public struct VerificationSummary: Codable, Sendable {
    public let status: VerificationStatus
    public let checks: [VerificationCheck]
}

public enum VerificationStatus: String, Codable, Sendable {
    case passed
    case failed
    case warning
    case notAttempted = "not_attempted"
}

public struct VerificationCheck: Codable, Sendable {
    public let condition: Postcondition
    public let passed: Bool
    public let detail: String?
}

public enum ActionVerifier {

    public static func matchesElement(_ element: UnifiedElement, query: String) -> Bool {
        element.id == query || element.label?.localizedCaseInsensitiveContains(query) == true
    }

    public static func verify(
        post: Observation,
        conditions: [Postcondition]
    ) -> VerificationSummary {
        var checks: [VerificationCheck] = []
        var allPassed = true

        for condition in conditions {
            let passed = verify(post: post, condition: condition)
            if !passed {
                allPassed = false
            }
            checks.append(VerificationCheck(
                condition: condition,
                passed: passed,
                detail: passed ? nil : "Condition failed"
            ))
        }

        return VerificationSummary(
            status: conditions.isEmpty ? .notAttempted : (allPassed ? .passed : .failed),
            checks: checks
        )
    }

    public static func verify(
        post: Observation,
        condition: Postcondition
    ) -> Bool {

        switch condition {

        case .elementFocused(let id):
            return post.focusedElementID == id

        case .elementAppeared(let id):
            return post.elements.contains { $0.id == id }

        case .elementDisappeared(let id):
            return !post.elements.contains { $0.id == id }

        case .elementValueEquals(let id, let value):
            return post.elements.first(where: { $0.id == id })?.value == value
        }
    }
}
