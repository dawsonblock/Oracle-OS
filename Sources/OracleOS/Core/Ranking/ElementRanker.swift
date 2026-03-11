import Foundation

public struct ElementRanker {

    public static func rank(
        elements: [UnifiedElement],
        query: ElementQuery
    ) -> [ElementCandidate] {

        var results: [ElementCandidate] = []

        for element in elements {

            let (score, reasons) =
                ElementMatcher.score(
                    element: element,
                    query: query
                )

            if score > 0 {

                results.append(
                    ElementCandidate(
                        element: element,
                        score: score,
                        reasons: reasons
                    )
                )
            }
        }

        return results.sorted { $0.score > $1.score }
    }
}
