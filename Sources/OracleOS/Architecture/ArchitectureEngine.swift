import Foundation

public final class ArchitectureEngine: @unchecked Sendable {
    private let dependencyAnalyzer: DependencyAnalyzer
    private let impactAnalyzer: ChangeImpactAnalyzer
    private let invariantChecker: InvariantChecker
    private let refactorPlanner: RefactorPlanner

    public init(
        dependencyAnalyzer: DependencyAnalyzer = DependencyAnalyzer(),
        impactAnalyzer: ChangeImpactAnalyzer = ChangeImpactAnalyzer(),
        invariantChecker: InvariantChecker = InvariantChecker(),
        refactorPlanner: RefactorPlanner = RefactorPlanner()
    ) {
        self.dependencyAnalyzer = dependencyAnalyzer
        self.impactAnalyzer = impactAnalyzer
        self.invariantChecker = invariantChecker
        self.refactorPlanner = refactorPlanner
    }

    public func review(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        candidatePaths: [String]
    ) -> ArchitectureReview {
        let highImpact = impactAnalyzer.shouldReview(goalDescription: goalDescription, candidatePaths: candidatePaths)
        let affectedModules = impactAnalyzer.affectedModules(for: candidatePaths)
        let moduleGraph = ArchitectureModuleGraph.build(from: snapshot)

        guard highImpact else {
            return ArchitectureReview(
                triggered: false,
                affectedModules: affectedModules,
                findings: [],
                refactorProposal: nil,
                riskScore: 0,
                governanceReport: .empty
            )
        }

        let dependencyFindings = dependencyAnalyzer.findings(in: moduleGraph)
        let governanceReport = invariantChecker.report(
            goalDescription: goalDescription,
            affectedModules: affectedModules,
            candidatePaths: candidatePaths,
            snapshot: snapshot
        )
        let governanceFindings = governanceReport.violations.map { $0.asArchitectureFinding() }
        let findings = (dependencyFindings + governanceFindings)
            .sorted { lhs, rhs in lhs.riskScore > rhs.riskScore }
        let proposal = refactorPlanner.proposal(from: findings)
        let riskScore = findings.map(\.riskScore).max() ?? 0.25

        return ArchitectureReview(
            triggered: true,
            affectedModules: affectedModules,
            findings: findings,
            refactorProposal: proposal,
            riskScore: riskScore,
            governanceReport: governanceReport
        )
    }
}
