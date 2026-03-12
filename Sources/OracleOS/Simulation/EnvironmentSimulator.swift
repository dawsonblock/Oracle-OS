import Foundation

public struct SimulationInput: Sendable {
    public let state: ReasoningPlanningState
    public let operators: [Operator]
    public let graphHints: [String]
    public let memoryHints: [String]

    public init(
        state: ReasoningPlanningState,
        operators: [Operator],
        graphHints: [String] = [],
        memoryHints: [String] = []
    ) {
        self.state = state
        self.operators = operators
        self.graphHints = graphHints
        self.memoryHints = memoryHints
    }
}

public struct SimulationStep: Sendable {
    public let operator_: Operator
    public let inputState: ReasoningPlanningState
    public let outputState: ReasoningPlanningState
    public let transitionProbability: Double
    public let notes: [String]

    public init(
        operator_: Operator,
        inputState: ReasoningPlanningState,
        outputState: ReasoningPlanningState,
        transitionProbability: Double,
        notes: [String] = []
    ) {
        self.operator_ = operator_
        self.inputState = inputState
        self.outputState = outputState
        self.transitionProbability = transitionProbability
        self.notes = notes
    }
}

public struct SimulationResult: Sendable {
    public let steps: [SimulationStep]
    public let finalState: ReasoningPlanningState
    public let overallProbability: Double
    public let cumulativeRisk: Double
    public let notes: [String]

    public init(
        steps: [SimulationStep],
        finalState: ReasoningPlanningState,
        overallProbability: Double,
        cumulativeRisk: Double,
        notes: [String] = []
    ) {
        self.steps = steps
        self.finalState = finalState
        self.overallProbability = overallProbability
        self.cumulativeRisk = cumulativeRisk
        self.notes = notes
    }
}

public final class EnvironmentSimulator: @unchecked Sendable {

    public init() {}

    public func simulate(input: SimulationInput) -> SimulationResult {
        var currentState = input.state
        var steps: [SimulationStep] = []
        var cumulativeProbability = 1.0
        var cumulativeRisk = 0.0
        var notes: [String] = []

        for op in input.operators {
            guard op.precondition(currentState) else {
                notes.append("operator \(op.name) precondition failed")
                break
            }

            let nextState = op.effect(currentState)
            let transitionProbability = transitionProbability(
                for: op,
                state: currentState,
                graphHints: input.graphHints,
                memoryHints: input.memoryHints
            )
            cumulativeProbability *= transitionProbability
            cumulativeRisk += op.risk

            var stepNotes: [String] = []
            if !input.graphHints.isEmpty {
                stepNotes.append("graph-informed transition")
            }
            if !input.memoryHints.isEmpty {
                stepNotes.append("memory-informed transition")
            }

            steps.append(SimulationStep(
                operator_: op,
                inputState: currentState,
                outputState: nextState,
                transitionProbability: transitionProbability,
                notes: stepNotes
            ))
            currentState = nextState
        }

        return SimulationResult(
            steps: steps,
            finalState: currentState,
            overallProbability: cumulativeProbability,
            cumulativeRisk: min(cumulativeRisk, 1.0),
            notes: notes
        )
    }

    private func transitionProbability(
        for op: Operator,
        state: ReasoningPlanningState,
        graphHints: [String],
        memoryHints: [String]
    ) -> Double {
        var probability: Double
        switch op.kind {
        case .dismissModal:
            probability = state.modalPresent ? 0.92 : 0.3
        case .openApplication:
            probability = state.targetApplication != nil ? 0.88 : 0.4
        case .navigateBrowser:
            probability = state.targetDomain != nil ? 0.85 : 0.35
        case .clickTarget:
            probability = state.visibleTargets.isEmpty ? 0.3 : 0.75
        case .applyPatch:
            probability = state.candidateWorkspacePaths.isEmpty ? 0.2 : 0.65
        case .runTests, .rerunTests:
            probability = state.repoOpen ? 0.8 : 0.25
        case .buildProject:
            probability = state.repoOpen ? 0.78 : 0.25
        case .revertPatch, .rollbackPatch:
            probability = state.patchApplied ? 0.85 : 0.3
        case .retryWithAlternateTarget:
            probability = state.visibleTargets.count > 1 ? 0.6 : 0.3
        case .focusWindow:
            probability = state.targetApplication != nil ? 0.9 : 0.4
        case .restartApplication:
            probability = state.targetApplication != nil ? 0.7 : 0.3
        }

        if graphHints.contains(where: { $0.contains(op.name) }) {
            probability = min(probability + 0.08, 0.98)
        }
        if memoryHints.contains(where: { $0.contains(op.name) }) {
            probability = min(probability + 0.06, 0.98)
        }

        return probability
    }
}
