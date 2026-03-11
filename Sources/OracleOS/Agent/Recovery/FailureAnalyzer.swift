public struct FailureAnalyzer {

    public static func classify(
        intent: ActionIntent,
        result: ActionResult,
        before: Observation,
        after: Observation,
        selectedCandidate: ElementCandidate? = nil,
        ambiguityScore: Double? = nil
    ) -> FailureClass? {

        if result.success == false {
            if let failureClass = result.failureClass,
               let decoded = FailureClass(rawValue: failureClass) {
                return decoded
            }

            if intent.agentKind == .code {
                switch intent.commandCategory {
                case CodeCommandCategory.build.rawValue, CodeCommandCategory.linter.rawValue:
                    return .buildFailed
                case CodeCommandCategory.test.rawValue, CodeCommandCategory.parseTestFailure.rawValue:
                    return .testFailed
                case CodeCommandCategory.editFile.rawValue, CodeCommandCategory.writeFile.rawValue, CodeCommandCategory.generatePatch.rawValue:
                    return .patchApplyFailed
                case CodeCommandCategory.gitPush.rawValue:
                    return .gitPolicyBlocked
                default:
                    if intent.workspaceRelativePath?.hasPrefix("/") == true || intent.workspaceRelativePath?.contains("../") == true {
                        return .workspaceScopeViolation
                    }
                }
            }

            if let ambiguityScore, ambiguityScore > 0.2 {
                return .elementAmbiguous
            }

            if intent.elementID != nil &&
               !after.elements.contains(where: { $0.id == intent.elementID }) {

                return .elementNotFound
            }

            if let selectedCandidate,
               before.elements.contains(where: { $0.id == selectedCandidate.element.id }),
               !after.elements.contains(where: { $0.id == selectedCandidate.element.id }) {
                return .staleObservation
            }

            if before.app != after.app {

                return .wrongFocus
            }

            if before.url != after.url,
               intent.postconditions.contains(where: { $0.kind == .urlContains || $0.kind == .windowTitleContains }) {
                return .navigationFailed
            }

            if before.stableHash() == after.stableHash(), result.verified == false {
                return .staleObservation
            }

            if result.verificationStatus == .failed {
                return .verificationFailed
            }

            return .actionFailed
        }

        return nil
    }
}
