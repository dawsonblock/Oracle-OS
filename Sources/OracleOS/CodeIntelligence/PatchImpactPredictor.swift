import Foundation

public struct PatchImpactPrediction: Sendable, Equatable {
    public let path: String
    public let predictedSuccessProbability: Double
    public let blastRadiusScore: Double
    public let affectedTestCount: Int
    public let reasons: [String]

    public init(
        path: String,
        predictedSuccessProbability: Double,
        blastRadiusScore: Double,
        affectedTestCount: Int,
        reasons: [String]
    ) {
        self.path = path
        self.predictedSuccessProbability = predictedSuccessProbability
        self.blastRadiusScore = blastRadiusScore
        self.affectedTestCount = affectedTestCount
        self.reasons = reasons
    }
}

public struct PatchImpactPredictor: Sendable {
    private let impactAnalyzer: RepositoryChangeImpactAnalyzer

    public init(impactAnalyzer: RepositoryChangeImpactAnalyzer = RepositoryChangeImpactAnalyzer()) {
        self.impactAnalyzer = impactAnalyzer
    }

    public func predict(
        patchTargets: [PatchTarget],
        in snapshot: RepositorySnapshot
    ) -> [PatchImpactPrediction] {
        patchTargets.map { target in
            let impact = target.impact
            let testCount = impact.affectedTests.count
            var reasons: [String] = []
            var successProbability = target.rootCauseCandidate.score

            if impact.blastRadiusScore > 0.5 {
                successProbability *= 0.8
                reasons.append("high blast radius reduces confidence")
            }
            if testCount > 0 {
                successProbability += 0.1
                reasons.append("\(testCount) affected tests available for validation")
            }
            if impact.dependentFiles.count > 10 {
                successProbability *= 0.9
                reasons.append("many dependents increase regression risk")
            }

            return PatchImpactPrediction(
                path: target.path,
                predictedSuccessProbability: min(1, max(0, successProbability)),
                blastRadiusScore: impact.blastRadiusScore,
                affectedTestCount: testCount,
                reasons: target.reasons + reasons
            )
        }
        .sorted { $0.predictedSuccessProbability > $1.predictedSuccessProbability }
    }
}
