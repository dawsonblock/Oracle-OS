import Foundation

public final class ExperimentManager: @unchecked Sendable {
    private let runner: ParallelRunner
    private let ranker: PatchRanker
    private let fileManager = FileManager.default

    public init(
        runner: ParallelRunner = ParallelRunner(),
        ranker: PatchRanker = PatchRanker()
    ) {
        self.runner = runner
        self.ranker = ranker
    }

    public func defaultExperimentsRoot(for workspaceRoot: URL) -> URL {
        workspaceRoot.appendingPathComponent(".oracle/experiments", isDirectory: true)
    }

    public func run(
        spec: ExperimentSpec,
        architectureRiskScore: Double = 0
    ) async throws -> [ExperimentResult] {
        let experimentsRoot = defaultExperimentsRoot(
            for: URL(fileURLWithPath: spec.workspaceRoot, isDirectory: true)
        )
        try fileManager.createDirectory(at: experimentsRoot, withIntermediateDirectories: true)

        let results = try await runner.run(
            spec: spec,
            experimentsRoot: experimentsRoot,
            architectureRiskScore: architectureRiskScore
        )
        let ranked = ranker.rank(results)
        let selectedID = ranked.first?.candidate.id

        let finalized = ranked.enumerated().map { _, result in
            ExperimentResult(
                id: result.id,
                experimentID: result.experimentID,
                candidate: result.candidate,
                sandboxPath: result.sandboxPath,
                commandResults: result.commandResults,
                diffSummary: result.diffSummary,
                architectureRiskScore: result.architectureRiskScore,
                selected: result.candidate.id == selectedID
            )
        }
        try persistResults(finalized, spec: spec, experimentsRoot: experimentsRoot)
        return finalized
    }

    public func replaySelected(
        from results: [ExperimentResult]
    ) -> CandidatePatch? {
        results.first(where: \.selected)?.candidate
    }

    private func persistResults(
        _ results: [ExperimentResult],
        spec: ExperimentSpec,
        experimentsRoot: URL
    ) throws {
        let resultURL = experimentsRoot
            .appendingPathComponent(spec.id, isDirectory: true)
            .appendingPathComponent("results.json", isDirectory: false)
        try fileManager.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(results)
        try data.write(to: resultURL)
    }
}
