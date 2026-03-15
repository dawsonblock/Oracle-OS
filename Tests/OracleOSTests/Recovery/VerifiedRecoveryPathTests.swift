import Foundation
import Testing
@testable import OracleOS

@Suite("Verified Recovery Path")
struct VerifiedRecoveryPathTests {

    @Test("Recovery plans carry failure class context")
    func recoveryPlansCarryContext() {
        let plan = RecoveryPlan(
            failureClass: .modalBlocking,
            recoveryOperators: [Operator(kind: .dismissModal)],
            estimatedRecoveryProbability: 0.8,
            notes: ["dismiss modal for recovery"]
        )
        #expect(plan.failureClass == .modalBlocking)
        #expect(!plan.recoveryOperators.isEmpty)
    }

    @Test("Recovery operator kinds map to valid operator registry entries")
    func recoveryOperatorKindsMapToRegistry() {
        for op in RecoveryOperator.defaults {
            let operatorInstance = Operator(kind: op.operatorKind)
            #expect(!operatorInstance.name.isEmpty)
            #expect(operatorInstance.baseCost >= 0)
        }
    }

    @Test("All default recovery strategies have non-empty descriptions")
    func allDefaultStrategiesHaveDescriptions() {
        for entry in RecoveryStrategyLibrary.shared.entries {
            #expect(!entry.name.isEmpty)
            #expect(!entry.description.isEmpty)
            #expect(!entry.applicableFailures.isEmpty)
        }
    }

    @Test("Failure classifier produces consistent classification")
    func failureClassifierConsistency() {
        let first = FailureClassifier.classify(errorDescription: "Target element not found")
        let second = FailureClassifier.classify(errorDescription: "Target element not found")
        #expect(first.failureClass == second.failureClass)
        #expect(first.confidence == second.confidence)
    }

    // MARK: - Comprehensive recovery tracking metrics

    @Test("LoopBudgetState starts with zero recovery success and failure counts")
    func budgetStateStartsWithZeroCounts() {
        let state = LoopBudgetState()
        #expect(state.recoveries == 0)
        #expect(state.recoverySuccesses == 0)
        #expect(state.recoveryFailures == 0)
    }

    @Test("registerRecoveryAttempt increments total recovery count")
    func registerRecoveryAttemptIncrementsTotal() {
        var state = LoopBudgetState()
        state.registerRecoveryAttempt()
        state.registerRecoveryAttempt()
        #expect(state.recoveries == 2)
        #expect(state.recoverySuccesses == 0)
        #expect(state.recoveryFailures == 0)
    }

    @Test("registerRecoverySuccess increments success count independently")
    func registerRecoverySuccessCount() {
        var state = LoopBudgetState()
        state.registerRecoveryAttempt()
        state.registerRecoverySuccess()
        state.registerRecoveryAttempt()
        state.registerRecoverySuccess()
        #expect(state.recoveries == 2)
        #expect(state.recoverySuccesses == 2)
        #expect(state.recoveryFailures == 0)
    }

    @Test("registerRecoveryFailure increments failure count independently")
    func registerRecoveryFailureCount() {
        var state = LoopBudgetState()
        state.registerRecoveryAttempt()
        state.registerRecoveryFailure()
        #expect(state.recoveries == 1)
        #expect(state.recoverySuccesses == 0)
        #expect(state.recoveryFailures == 1)
    }

    @Test("Recovery success and failure counts are tracked independently")
    func recoverySuccessAndFailureTrackedIndependently() {
        var state = LoopBudgetState()
        // Two successes, one failure
        state.registerRecoveryAttempt()
        state.registerRecoverySuccess()
        state.registerRecoveryAttempt()
        state.registerRecoverySuccess()
        state.registerRecoveryAttempt()
        state.registerRecoveryFailure()
        #expect(state.recoveries == 3)
        #expect(state.recoverySuccesses == 2)
        #expect(state.recoveryFailures == 1)
        #expect(state.recoverySuccesses + state.recoveryFailures == state.recoveries)
    }

    @Test("LoopOutcome carries recovery success and failure counts")
    func loopOutcomeCarriesRecoveryMetrics() {
        let outcome = LoopOutcome(
            reason: .goalAchieved,
            finalWorldState: nil,
            steps: 5,
            recoveries: 3,
            recoverySuccesses: 2,
            recoveryFailures: 1
        )
        #expect(outcome.recoveries == 3)
        #expect(outcome.recoverySuccesses == 2)
        #expect(outcome.recoveryFailures == 1)
    }

    @Test("LoopOutcome defaults recovery success and failure to zero")
    func loopOutcomeDefaultsRecoveryMetricsToZero() {
        let outcome = LoopOutcome(
            reason: .goalAchieved,
            finalWorldState: nil,
            steps: 3,
            recoveries: 0
        )
        #expect(outcome.recoverySuccesses == 0)
        #expect(outcome.recoveryFailures == 0)
    }
}
