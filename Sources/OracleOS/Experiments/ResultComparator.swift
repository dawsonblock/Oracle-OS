import Foundation

public struct ResultComparator: Sendable {
    public init() {}

    public func sort(_ results: [ExperimentResult]) -> [ExperimentResult] {
        results.sorted { lhs, rhs in
            if lhs.succeeded != rhs.succeeded {
                return lhs.succeeded && !rhs.succeeded
            }
            let lhsTouched = touchedFileCount(lhs.diffSummary)
            let rhsTouched = touchedFileCount(rhs.diffSummary)
            if lhsTouched != rhsTouched {
                return lhsTouched < rhsTouched
            }
            let lhsDiff = lhs.diffSummary.count
            let rhsDiff = rhs.diffSummary.count
            if lhsDiff != rhsDiff {
                return lhsDiff < rhsDiff
            }
            if lhs.architectureRiskScore != rhs.architectureRiskScore {
                return lhs.architectureRiskScore < rhs.architectureRiskScore
            }
            return lhs.elapsedMs < rhs.elapsedMs
        }
    }

    private func touchedFileCount(_ diffSummary: String) -> Int {
        diffSummary
            .split(separator: "\n")
            .filter { $0.contains("|") }
            .count
    }
}
