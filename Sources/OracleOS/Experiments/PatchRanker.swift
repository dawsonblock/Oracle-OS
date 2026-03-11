import Foundation

public struct PatchRanker: Sendable {
    private let comparator: ResultComparator

    public init(comparator: ResultComparator = ResultComparator()) {
        self.comparator = comparator
    }

    public func rank(_ results: [ExperimentResult]) -> [ExperimentResult] {
        comparator.sort(results)
    }
}
