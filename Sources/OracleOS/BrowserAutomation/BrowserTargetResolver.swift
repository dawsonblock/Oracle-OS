import Foundation

public struct BrowserTargetSelection: Sendable, Equatable {
    public let match: BrowserPageMatch
    public let ambiguityScore: Double
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
}
