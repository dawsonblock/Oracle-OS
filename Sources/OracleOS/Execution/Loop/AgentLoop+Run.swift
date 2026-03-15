import Foundation

@MainActor
extension AgentLoop {
    @discardableResult
    public func run(
        goal: Goal,
        budget: LoopBudget = LoopBudget(),
        surface: RuntimeSurface = .recipe
    ) async -> LoopOutcome {
        decisionCoordinator.setGoal(goal)
        let taskContext = TaskContext.from(
            goal: goal,
            workspaceRoot: goal.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )

        var runState = AgentLoopRunState()

        for stepIndex in 0..<budget.maxSteps {
            let stateBundle = stateCoordinator.buildState(
                taskContext: taskContext,
                lastAction: runState.lastAction
            )
            runState.latestWorldState = stateBundle.worldState

            if decisionCoordinator.goalReached(in: stateBundle) {
                return finalize(
                    reason: .goalAchieved,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex,
                    lastFailure: nil,
                    decision: nil,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            guard let decision = decisionCoordinator.decide(from: stateBundle) else {
                return finalize(
                    reason: .noViablePlan,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex,
                    lastFailure: nil,
                    decision: nil,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            runState.diagnostics.beginStep(stepIndex: stepIndex, decision: decision)

            if let budgetReason = runState.budgetState.registerPlannerSource(decision.source, budget: budget) {
                runState.diagnostics.recordTermination(stepIndex: stepIndex, reason: budgetReason)
                return finalize(
                    reason: budgetReason,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex,
                    lastFailure: nil,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            if decision.executionMode == .experiment, let experimentSpec = decision.experimentSpec {
                if let outcome = await experimentCoordinator.handle(
                    decision: decision,
                    experimentSpec: experimentSpec,
                    taskContext: taskContext,
                    worldState: stateBundle.worldState,
                    budgetState: &runState.budgetState,
                    step: stepIndex,
                    budget: budget,
                    diagnostics: &runState.diagnostics
                ) {
                    return outcome
                }
                continue
            }

            let prepared: PreparedLoopAction
            do {
                prepared = try executionCoordinator.prepare(
                    decision: decision,
                    stateBundle: stateBundle,
                    surface: surface
                )
                runState.diagnostics.recordPreparation(
                    stepIndex: stepIndex,
                    outcome: .ready
                )
            } catch let error as SkillResolutionError {
                let termination = await handlePreparationFailure(
                    failure: error.failureClass,
                    decision: decision,
                    stateBundle: stateBundle,
                    budget: budget,
                    budgetState: &runState.budgetState,
                    diagnostics: &runState.diagnostics,
                    stepIndex: stepIndex
                )
                if let outcome = termination.outcome {
                    return finalizeFromChild(
                        outcome: outcome,
                        decision: decision,
                        taskContext: taskContext,
                        runState: runState
                    )
                }
                continue
            } catch let error as CodeSkillResolutionError {
                let termination = await handlePreparationFailure(
                    failure: error.failureClass,
                    decision: decision,
                    stateBundle: stateBundle,
                    budget: budget,
                    budgetState: &runState.budgetState,
                    diagnostics: &runState.diagnostics,
                    stepIndex: stepIndex
                )
                if let outcome = termination.outcome {
                    return finalizeFromChild(
                        outcome: outcome,
                        decision: decision,
                        taskContext: taskContext,
                        runState: runState
                    )
                }
                continue
            } catch {
                runState.diagnostics.recordPreparation(
                    stepIndex: stepIndex,
                    outcome: .failed,
                    failure: .actionFailed,
                    notes: decision.notes + ["unexpected preparation failure"]
                )
                return finalize(
                    reason: .unrecoverableFailure,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex + 1,
                    lastFailure: .actionFailed,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            if let policyTermination = executionCoordinator.terminationReason(for: prepared) {
                runState.diagnostics.recordPolicy(
                    stepIndex: stepIndex,
                    outcome: .blocked,
                    notes: decision.notes + [policyTermination == .approvalTimeout ? "approval required before loop execution" : "policy precheck blocked execution"]
                )
                return finalize(
                    reason: policyTermination,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex,
                    lastFailure: nil,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            runState.diagnostics.recordPolicy(stepIndex: stepIndex, outcome: .allowed)
            let execution = executionCoordinator.execute(
                preparedAction: prepared,
                decision: decision,
                budgetState: &runState.budgetState,
                budget: budget
            )
            runState.lastAction = execution.intent

            if let budgetReason = execution.budgetTerminationReason {
                runState.diagnostics.recordExecution(
                    stepIndex: stepIndex,
                    success: false,
                    failure: .patchApplyFailed,
                    notes: decision.notes + ["code budget exceeded"]
                )
                runState.diagnostics.recordTermination(stepIndex: stepIndex, reason: budgetReason)
                return finalize(
                    reason: budgetReason,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex + 1,
                    lastFailure: .patchApplyFailed,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            if execution.approvalPending {
                runState.diagnostics.recordExecutionSkipped(
                    stepIndex: stepIndex,
                    notes: decision.notes + ["execution paused pending approval"]
                )
                runState.diagnostics.recordTermination(stepIndex: stepIndex, reason: .approvalTimeout)
                return finalize(
                    reason: .approvalTimeout,
                    finalWorldState: stateBundle.worldState,
                    steps: stepIndex + 1,
                    lastFailure: nil,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            }

            if execution.actionResult.success {
                runState.diagnostics.recordExecution(
                    stepIndex: stepIndex,
                    success: true,
                    notes: decision.notes
                )
                learningCoordinator.recordSuccess(
                    decision: decision,
                    intent: execution.intent,
                    taskContext: taskContext
                )
                let afterStateBundle = stateCoordinator.buildState(
                    taskContext: taskContext,
                    lastAction: execution.intent
                )
                runState.latestWorldState = afterStateBundle.worldState
                if decisionCoordinator.goalReached(in: afterStateBundle) {
                    return finalize(
                        reason: .goalAchieved,
                        finalWorldState: afterStateBundle.worldState,
                        steps: stepIndex + 1,
                        lastFailure: nil,
                        decision: decision,
                        taskContext: taskContext,
                        runState: runState
                    )
                }
                continue
            }

            let afterStateBundle = stateCoordinator.buildState(
                taskContext: taskContext,
                lastAction: execution.intent
            )
            runState.latestWorldState = afterStateBundle.worldState
            let failure = FailureClassifier.classifyAction(
                intent: execution.intent,
                result: execution.actionResult,
                before: stateBundle.observation,
                after: afterStateBundle.observation,
                selectedCandidate: execution.selectedCandidate,
                ambiguityScore: execution.selectedCandidate?.ambiguityScore
            ) ?? .actionFailed

            learningCoordinator.recordFailure(
                failure: failure,
                stateBundle: afterStateBundle
            )
            runState.diagnostics.recordExecution(
                stepIndex: stepIndex,
                success: false,
                failure: failure,
                notes: decision.notes
            )

            let termination = await recoveryCoordinator.recover(
                from: failure,
                decision: decision,
                stateBundle: afterStateBundle,
                budget: budget,
                budgetState: &runState.budgetState,
                diagnostics: &runState.diagnostics,
                stepIndex: stepIndex,
                failureNote: "bounded recovery failed",
                successNote: "bounded recovery succeeded"
            )
            if let outcome = termination.outcome {
                return finalizeFromChild(
                    outcome: outcome,
                    decision: decision,
                    taskContext: taskContext,
                    runState: runState
                )
            }
        }

        return finalize(
            reason: .maxSteps,
            finalWorldState: runState.latestWorldState,
            steps: budget.maxSteps,
            lastFailure: nil,
            decision: nil,
            taskContext: taskContext,
            runState: runState
        )
    }

    public func run(goal: String, state: WorldState) async {
        let interpretedGoal = planner.interpretGoal(goal)
        planner.setGoal(interpretedGoal)
        _ = planner.nextStep(worldState: state, graphStore: graphStore)
    }

    private func finalizeFromChild(
        outcome: LoopOutcome,
        decision: PlannerDecision?,
        taskContext: TaskContext,
        runState: AgentLoopRunState
    ) -> LoopOutcome {
        finalize(
            reason: outcome.reason,
            finalWorldState: outcome.finalWorldState,
            steps: outcome.steps,
            lastFailure: outcome.lastFailure,
            decision: decision,
            taskContext: taskContext,
            runState: AgentLoopRunState(
                latestWorldState: outcome.finalWorldState ?? runState.latestWorldState,
                lastAction: runState.lastAction,
                diagnostics: outcome.diagnostics,
                budgetState: LoopBudgetState(
                    recoveries: outcome.recoveries,
                    consecutiveExplorationSteps: runState.budgetState.consecutiveExplorationSteps,
                    patchIterations: runState.budgetState.patchIterations,
                    buildAttempts: runState.budgetState.buildAttempts,
                    testAttempts: runState.budgetState.testAttempts
                )
            )
        )
    }

    private func finalize(
        reason: LoopTerminationReason,
        finalWorldState: WorldState?,
        steps: Int,
        lastFailure: FailureClass?,
        decision: PlannerDecision?,
        taskContext: TaskContext,
        runState: AgentLoopRunState
    ) -> LoopOutcome {
        var diagnostics = runState.diagnostics
        diagnostics.recordTermination(
            stepIndex: diagnostics.stepSummaries.last?.stepIndex,
            reason: reason
        )
        let outcome = LoopOutcome(
            reason: reason,
            finalWorldState: finalWorldState,
            steps: steps,
            recoveries: runState.budgetState.recoveries,
            lastFailure: lastFailure,
            diagnostics: diagnostics
        )
        learningCoordinator.finalize(
            outcome: outcome,
            taskContext: taskContext,
            decision: decision
        )
        return outcome
    }

    private func handlePreparationFailure(
        failure: FailureClass,
        decision: PlannerDecision,
        stateBundle: LoopStateBundle,
        budget: LoopBudget,
        budgetState: inout LoopBudgetState,
        diagnostics: inout LoopDiagnostics,
        stepIndex: Int
    ) async -> LoopTermination {
        diagnostics.recordPreparation(
            stepIndex: stepIndex,
            outcome: .failed,
            failure: failure,
            notes: decision.notes + ["preparation failure"]
        )
        return await recoveryCoordinator.recover(
            from: failure,
            decision: decision,
            stateBundle: stateBundle,
            budget: budget,
            budgetState: &budgetState,
            diagnostics: &diagnostics,
            stepIndex: stepIndex,
            failureNote: "recovery failed after preparation failure",
            successNote: "recovery succeeded after preparation failure"
        )
    }
}
