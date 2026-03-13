import Foundation

public struct ImprovementPlan: Sendable {
    public let candidates: [ImprovementCandidate]
    public let promoted: [ImprovementCandidate]
    public let deferred: [ImprovementCandidate]
    public let rejected: [ImprovementCandidate]
    public let notes: [String]

    public init(
        candidates: [ImprovementCandidate],
        promoted: [ImprovementCandidate],
        deferred: [ImprovementCandidate],
        rejected: [ImprovementCandidate],
        notes: [String] = []
    ) {
        self.candidates = candidates
        self.promoted = promoted
        self.deferred = deferred
        self.rejected = rejected
        self.notes = notes
    }
}

public final class ImprovementPlanner: @unchecked Sendable {
    private let minimumConfidence: Double
    private let minimumBenefit: Double

    public init(
        minimumConfidence: Double = 0.5,
        minimumBenefit: Double = 0.3
    ) {
        self.minimumConfidence = minimumConfidence
        self.minimumBenefit = minimumBenefit
    }

    public func evaluate(candidates: [ImprovementCandidate]) -> ImprovementPlan {
        var promoted: [ImprovementCandidate] = []
        var deferred: [ImprovementCandidate] = []
        var rejected: [ImprovementCandidate] = []

        for candidate in candidates {
            if candidate.confidence >= minimumConfidence
                && candidate.expectedBenefit >= minimumBenefit
                && candidate.risk.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "high"
            {
                promoted.append(candidate)
            } else if candidate.confidence >= minimumConfidence * 0.6
                && candidate.expectedBenefit >= minimumBenefit * 0.6
            {
                deferred.append(candidate)
            } else {
                rejected.append(candidate)
            }
        }

        return ImprovementPlan(
            candidates: candidates,
            promoted: promoted.sorted { $0.expectedBenefit > $1.expectedBenefit },
            deferred: deferred,
            rejected: rejected,
            notes: [
                "evaluated \(candidates.count) candidate(s)",
                "promoted \(promoted.count), deferred \(deferred.count), rejected \(rejected.count)",
            ]
        )
    }
}
