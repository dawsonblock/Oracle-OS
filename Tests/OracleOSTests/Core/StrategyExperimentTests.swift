import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy Experiment")
struct StrategyExperimentTests {

    @Test("Experiment returns insufficient data when trials are few")
    func experimentReturnsInsufficientData() {
        let experiment = StrategyExperiment(minimumTrials: 3)
        experiment.recordTrial(ExperimentTrial(
            candidateID: "c1", taskID: "t1", succeeded: true
        ))

        let verdict = experiment.evaluate(candidateID: "c1")
        #expect(verdict.verdict == .insufficientData)
        #expect(verdict.trialCount == 1)
    }

    @Test("Experiment promotes candidate with clear improvement")
    func experimentPromotesCandidate() {
        let experiment = StrategyExperiment(minimumTrials: 3, minimumImprovement: 0.1)
        for i in 0..<4 {
            experiment.recordTrial(ExperimentTrial(
                candidateID: "c1",
                taskID: "t\(i)",
                succeeded: true,
                baselineSuccessRate: 0.5
            ))
        }

        let verdict = experiment.evaluate(candidateID: "c1")
        #expect(verdict.verdict == .promote)
        #expect(verdict.successRate == 1.0)
        #expect(verdict.improvementOverBaseline > 0)
    }

    @Test("Experiment rejects candidate performing worse than baseline")
    func experimentRejectsCandidate() {
        let experiment = StrategyExperiment(minimumTrials: 3, minimumImprovement: 0.1)
        for i in 0..<3 {
            experiment.recordTrial(ExperimentTrial(
                candidateID: "c2",
                taskID: "t\(i)",
                succeeded: false,
                baselineSuccessRate: 0.8
            ))
        }

        let verdict = experiment.evaluate(candidateID: "c2")
        #expect(verdict.verdict == .reject)
        #expect(verdict.improvementOverBaseline < 0)
    }

    @Test("Experiment returns inconclusive for marginal improvement")
    func experimentReturnsInconclusive() {
        let experiment = StrategyExperiment(minimumTrials: 3, minimumImprovement: 0.2)

        // 2/3 succeed, baseline 0.6 → success rate 0.67, improvement ~0.07
        experiment.recordTrial(ExperimentTrial(candidateID: "c3", taskID: "t1", succeeded: true, baselineSuccessRate: 0.6))
        experiment.recordTrial(ExperimentTrial(candidateID: "c3", taskID: "t2", succeeded: true, baselineSuccessRate: 0.6))
        experiment.recordTrial(ExperimentTrial(candidateID: "c3", taskID: "t3", succeeded: false, baselineSuccessRate: 0.6))

        let verdict = experiment.evaluate(candidateID: "c3")
        #expect(verdict.verdict == .inconclusive)
    }

    @Test("Experiment tracks trials per candidate independently")
    func experimentTracksTrialsIndependently() {
        let experiment = StrategyExperiment(minimumTrials: 2)

        experiment.recordTrial(ExperimentTrial(candidateID: "a", taskID: "t1", succeeded: true))
        experiment.recordTrial(ExperimentTrial(candidateID: "a", taskID: "t2", succeeded: true))
        experiment.recordTrial(ExperimentTrial(candidateID: "b", taskID: "t3", succeeded: false))

        let trialsA = experiment.trials(for: "a")
        let trialsB = experiment.trials(for: "b")
        #expect(trialsA.count == 2)
        #expect(trialsB.count == 1)

        let verdictA = experiment.evaluate(candidateID: "a")
        let verdictB = experiment.evaluate(candidateID: "b")
        #expect(verdictA.trialCount == 2)
        #expect(verdictB.verdict == .insufficientData)
    }

    @Test("ExperimentVerdictKind has all expected cases")
    func experimentVerdictKindCases() {
        let kinds: [ExperimentVerdictKind] = [
            .promote, .reject, .inconclusive, .insufficientData
        ]
        #expect(kinds.count == 4)
    }
}
