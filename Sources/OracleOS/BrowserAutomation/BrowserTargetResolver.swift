import Foundation

public struct BrowserTargetSelection: Sendable, Equatable {
    public let match: BrowserPageMatch
    public let ambiguityScore: Double
}

public struct BrowserTargetScore: Sendable {
    public let textSimilarity: Double
    public let roleMatch: Double
    public let visibilityScore: Double
    public let totalScore: Double
    public let notes: [String]

    public init(
        textSimilarity: Double,
        roleMatch: Double,
        visibilityScore: Double,
        notes: [String] = []
    ) {
        self.textSimilarity = textSimilarity
        self.roleMatch = roleMatch
        self.visibilityScore = visibilityScore
        self.totalScore = 0.50 * textSimilarity + 0.30 * roleMatch + 0.20 * visibilityScore
        self.notes = notes
    }
}

public enum BrowserTargetResolver {
    public static let minimumScore = 0.6
    public static let maximumAmbiguity = 0.2

    public static func resolve(
        query: ElementQuery,
        in snapshot: PageSnapshot
    ) throws -> BrowserTargetSelection {
        let matches = BrowserPageQuery.query(snapshot: snapshot, text: query.text, role: query.role)
        guard let best = matches.first else {
            throw SkillResolutionError.noCandidate(query.text ?? query.role ?? "browser target")
        }
        guard best.score >= minimumScore else {
            throw SkillResolutionError.noCandidate(query.text ?? query.role ?? "browser target")
        }

        let secondScore = matches.dropFirst().first?.score ?? 0
        let ambiguity = max(0, best.score - secondScore < maximumAmbiguity ? 1 - (best.score - secondScore) : 0)
        if best.score - secondScore < maximumAmbiguity {
            throw SkillResolutionError.ambiguousTarget(query.text ?? query.role ?? "browser target", ambiguity)
        }

        return BrowserTargetSelection(match: best, ambiguityScore: ambiguity)
    }

    public static func score(
        query: ElementQuery,
        in snapshot: PageSnapshot
    ) -> [BrowserTargetScore] {
        let matches = BrowserPageQuery.query(snapshot: snapshot, text: query.text, role: query.role)
        return matches.map { match in
            let textSim = match.score
            let roleMatch: Double = query.role != nil && match.element.role == query.role ? 1.0 : 0.5
            let visibilityScore: Double = 1.0
            var notes: [String] = []
            if textSim >= minimumScore {
                notes.append("strong text match")
            }
            if query.role != nil && match.element.role == query.role {
                notes.append("exact role match")
            }
            return BrowserTargetScore(
                textSimilarity: textSim,
                roleMatch: roleMatch,
                visibilityScore: visibilityScore,
                notes: notes
            )
        }
    }
}
