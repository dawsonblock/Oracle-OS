import Foundation

public struct ElementCandidate {

    public let element: UnifiedElement
    public let score: Double
    public let reasons: [String]

    public init(
        element: UnifiedElement,
        score: Double,
        reasons: [String]
    ) {
        self.element = element
        self.score = score
        self.reasons = reasons
    }
}
