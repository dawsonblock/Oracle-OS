import Foundation

public struct ElementMatcher {

    public static func score(
        element: UnifiedElement,
        query: ElementQuery
    ) -> (Double, [String]) {

        var score: Double = 0
        var reasons: [String] = []

        if query.visibleOnly && !element.visible {
            return (0, ["not visible"])
        }

        if let role = query.role,
           element.role?.lowercased() == role.lowercased() {

            score += 2
            reasons.append("role match")
        }

        if let text = query.text {

            let q = text.lowercased()

            if element.label?.lowercased().contains(q) == true {

                score += 3
                reasons.append("label match")
            }

            if element.value?.lowercased().contains(q) == true {

                score += 2
                reasons.append("value match")
            }
        }

        if query.clickable == true {

            if element.role?.contains("button") == true {

                score += 1
                reasons.append("clickable role")
            }
        }

        score += element.confidence

        return (score, reasons)
    }
}
