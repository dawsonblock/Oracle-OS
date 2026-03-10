import Foundation

public extension WorldState {

    func find(
        query: ElementQuery
    ) -> ElementCandidate? {

        let ranked =
            ElementRanker.rank(
                elements: observation.elements,
                query: query
            )

        return ranked.first
    }

}
