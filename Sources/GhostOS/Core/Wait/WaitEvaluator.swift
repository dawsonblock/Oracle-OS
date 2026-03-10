import Foundation

@MainActor
public enum WaitEvaluator {
    public static func isSatisfied(_ condition: WaitCondition, appName: String?) -> Bool {
        let observation = ObservationBuilder.capture(appName: appName)

        switch condition {
        case .urlContains(let value):
            return observation.url?.localizedCaseInsensitiveContains(value) == true

        case .titleContains(let value):
            return observation.windowTitle?.localizedCaseInsensitiveContains(value) == true

        case .elementExists(let target):
            return observation.elements.contains(where: { ActionVerifier.matchesElement($0, query: target) })

        case .elementGone(let target):
            return !observation.elements.contains(where: { ActionVerifier.matchesElement($0, query: target) })

        case .urlChanged(let baseline):
            return observation.url != baseline && observation.url != nil

        case .titleChanged(let baseline):
            return observation.windowTitle != baseline && observation.windowTitle != nil

        case .focusEquals(let target):
            return observation.focusedElementID == target

        case .valueEquals(let target, let value):
            // This would need element lookup which is expensive in a poll loop, 
            // but for now we follow the existing logic's intent.
            return observation.elements.first(where: { $0.id == target })?.value == value
            
        case .elementFocused(let target):
            return observation.focusedElementID == target
            
        case .screenStable:
            // Placeholder for actual stability check
            return true
        }
    }
}
