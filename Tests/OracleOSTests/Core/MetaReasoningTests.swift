import Foundation
import Testing
@testable import OracleOS

@Suite("Meta-Reasoning")
struct MetaReasoningTests {

    // MARK: - Performance Analyzer

    @Test("Performance analyzer detects bottlenecks from repeated actions")
    func performanceAnalyzerDetectsBottlenecks() {
        let analyzer = PerformanceAnalyzer()
        let events = (0..<5).map { i in
            makeTraceEvent(stepID: i, actionName: "click", success: true)
        }

        let report = analyzer.analyze(taskID: "task-1", events: events, outcome: .success)

        #expect(report.taskID == "task-1")
        #expect(report.outcome == .success)
        #expect(report.bottlenecks.contains { $0.contains("repeated action") })
    }

    @Test("Performance analyzer reports failure causes")
    func performanceAnalyzerReportsFailureCauses() {
        let analyzer = PerformanceAnalyzer()
        let events = [
            makeTraceEvent(stepID: 0, actionName: "run_tests", success: false),
            makeTraceEvent(stepID: 1, actionName: "run_tests", success: false),
            makeTraceEvent(stepID: 2, actionName: "apply_patch", success: true),
        ]

        let report = analyzer.analyze(taskID: "task-2", events: events, outcome: .failure)

        #expect(!report.failureCauses.isEmpty)
        #expect(report.failureCauses.contains { $0.contains("run_tests") })
    }

    @Test("Performance analyzer assesses strategy effectiveness")
    func performanceAnalyzerAssessesStrategies() {
        let analyzer = PerformanceAnalyzer()
        let events = [
            makeTraceEvent(stepID: 0, actionName: "apply_patch", success: true),
            makeTraceEvent(stepID: 1, actionName: "apply_patch", success: true),
            makeTraceEvent(stepID: 2, actionName: "apply_patch", success: false),
        ]

        let report = analyzer.analyze(taskID: "task-3", events: events, outcome: .success)

        let patchStrategy = report.strategyEffectiveness.first { $0.strategyName == "apply_patch" }
        #expect(patchStrategy != nil)
        #expect(patchStrategy?.wasEffective == true)
        #expect((patchStrategy?.contributionScore ?? 0) > 0.5)
    }

    @Test("Performance analyzer counts recovery events")
    func performanceAnalyzerCountsRecovery() {
        let analyzer = PerformanceAnalyzer()
        let events = [
            makeTraceEvent(stepID: 0, actionName: "click", success: true, recoveryTagged: true),
            makeTraceEvent(stepID: 1, actionName: "click", success: true, recoveryTagged: true),
            makeTraceEvent(stepID: 2, actionName: "click", success: true),
        ]

        let report = analyzer.analyze(taskID: "task-4", events: events, outcome: .success)
        #expect(report.recoveryCount == 2)
    }

    @Test("Performance analyzer detects redundant steps")
    func performanceAnalyzerDetectsRedundant() {
        let analyzer = PerformanceAnalyzer()
        let events = [
            makeTraceEvent(stepID: 0, actionName: "click", success: true),
            makeTraceEvent(stepID: 1, actionName: "click", success: true),
        ]

        let report = analyzer.analyze(taskID: "task-5", events: events, outcome: .success)
        #expect(!report.redundantSteps.isEmpty)
    }

    // MARK: - Strategy Generator

    @Test("Strategy generator produces workflow candidate for clean success")
    func strategyGeneratorProducesWorkflowCandidate() async {
        let generator = StrategyGenerator()
        let report = PerformanceReport(
            taskID: "task-ok",
            outcome: .success,
            recoveryCount: 0
        )

        let candidates = await generator.generate(from: report)
        #expect(candidates.contains { $0.kind == .newWorkflow })
    }

    @Test("Strategy generator produces recovery tactic for high recovery count")
    func strategyGeneratorProducesRecoveryTactic() async {
        let generator = StrategyGenerator()
        let report = PerformanceReport(
            taskID: "task-recovery",
            outcome: .success,
            recoveryCount: 5
        )

        let candidates = await generator.generate(from: report)
        #expect(candidates.contains { $0.kind == .newRecoveryTactic })
    }

    @Test("Strategy generator produces heuristic improvements for bottlenecks")
    func strategyGeneratorProducesHeuristicImprovements() async {
        let generator = StrategyGenerator()
        let report = PerformanceReport(
            taskID: "task-slow",
            outcome: .failure,
            bottlenecks: ["repeated action: click (6 times)"],
            recoveryCount: 0
        )

        let candidates = await generator.generate(from: report)
        #expect(candidates.contains { $0.kind == .plannerHeuristic })
    }

    // MARK: - Improvement Planner

    @Test("Improvement planner promotes high-confidence high-benefit candidates")
    func improvementPlannerPromotesGoodCandidates() {
        let planner = ImprovementPlanner()
        let candidates = [
            ImprovementCandidate(kind: .newWorkflow, description: "good workflow", expectedBenefit: 0.7, confidence: 0.8),
            ImprovementCandidate(kind: .plannerHeuristic, description: "weak idea", expectedBenefit: 0.1, confidence: 0.2),
            ImprovementCandidate(kind: .newRecoveryTactic, description: "medium idea", expectedBenefit: 0.25, confidence: 0.4),
        ]

        let plan = planner.evaluate(candidates: candidates)
        #expect(plan.promoted.count == 1)
        #expect(plan.promoted.first?.kind == .newWorkflow)
        #expect(plan.rejected.contains { $0.description == "weak idea" })
    }

    @Test("Improvement planner rejects high-risk candidates")
    func improvementPlannerRejectsHighRisk() {
        let planner = ImprovementPlanner()
        let candidates = [
            ImprovementCandidate(kind: .plannerHeuristic, description: "risky change", expectedBenefit: 0.8, confidence: 0.9, risk: "high"),
        ]

        let plan = planner.evaluate(candidates: candidates)
        #expect(plan.promoted.isEmpty)
    }

    // MARK: - Self Evaluation

    @Test("Self evaluation tracks metrics across multiple reports")
    func selfEvaluationTracksMetrics() {
        let eval = SelfEvaluation()
        eval.record(PerformanceReport(taskID: "t1", outcome: .success, recoveryCount: 0))
        eval.record(PerformanceReport(taskID: "t2", outcome: .failure, recoveryCount: 2))
        eval.record(PerformanceReport(taskID: "t3", outcome: .success, recoveryCount: 1))

        let metrics = eval.metrics
        #expect(metrics.totalTasks == 3)
        #expect(metrics.taskSuccessRate > 0.6)
        #expect(metrics.taskSuccessRate < 0.7)
    }

    @Test("Self evaluation returns empty metrics when no reports recorded")
    func selfEvaluationReturnsEmptyMetrics() {
        let eval = SelfEvaluation()
        let metrics = eval.metrics
        #expect(metrics.totalTasks == 0)
        #expect(metrics.taskSuccessRate == 0)
    }

    @Test("Self evaluation returns recent reports in order")
    func selfEvaluationReturnsRecentReports() {
        let eval = SelfEvaluation()
        for i in 0..<15 {
            eval.record(PerformanceReport(taskID: "t\(i)", outcome: .success))
        }

        let recent = eval.recentReports(limit: 5)
        #expect(recent.count == 5)
        #expect(recent.first?.taskID == "t10")
        #expect(recent.last?.taskID == "t14")
    }

    // MARK: - Helpers

    private func makeTraceEvent(
        stepID: Int,
        actionName: String,
        success: Bool,
        recoveryTagged: Bool = false,
        planningStateID: String? = nil
    ) -> TraceEvent {
        TraceEvent(
            sessionID: "session-1",
            taskID: "task-1",
            stepID: stepID,
            toolName: nil,
            actionName: actionName,
            planningStateID: planningStateID,
            verified: success,
            success: success,
            recoveryTagged: recoveryTagged,
            blockedByPolicy: false,
            agentKind: "os",
            knowledgeTier: nil,
            elapsedMs: 10
        )
    }
}
