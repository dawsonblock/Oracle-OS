import Foundation

// WorkflowSynthesizer may only promote reusable, parameterized structure from
// repeated verified traces. Episode-specific residue must remain in trace or
// artifact storage unless it is explicitly lifted into typed parameters.
public struct WorkflowSynthesizer: Sendable {
    private let replayValidator: WorkflowReplayValidator
    private let promotionPolicy: WorkflowPromotionPolicy

    public init(
        replayValidator: WorkflowReplayValidator = WorkflowReplayValidator(),
        promotionPolicy: WorkflowPromotionPolicy = WorkflowPromotionPolicy()
    ) {
        self.replayValidator = replayValidator
        self.promotionPolicy = promotionPolicy
    }

    public func synthesize(
        goalPattern: String,
        events: [TraceEvent]
    ) -> [WorkflowPlan] {
        TraceSegmenter.repeatedSegments(events: events)
            .map { candidatePlan(goalPattern: goalPattern, group: $0) }
            .sorted { lhs, rhs in
                if lhs.successRate == rhs.successRate {
                    return lhs.goalPattern < rhs.goalPattern
                }
                return lhs.successRate > rhs.successRate
            }
    }

    private func candidatePlan(
        goalPattern: String,
        group: RepeatedTraceSegment
    ) -> WorkflowPlan {
        let representative = group.segments[0]
        let parameters = ParameterExtractor.extract(from: group.segments)
        let steps = representative.events.map(step(from:))
        let replayValidationSuccess = replayValidator.validate(
            plan: WorkflowPlan(
                agentKind: representative.agentKind,
                goalPattern: goalPattern,
                steps: steps,
                parameterSlots: parameters.map(\.name),
                successRate: successRate(for: group),
                sourceTraceRefs: sourceTraceRefs(for: group),
                sourceGraphEdgeRefs: sourceGraphEdgeRefs(for: group),
                evidenceTiers: representative.evidenceTiers,
                repeatedTraceSegmentCount: group.segments.count
            ),
            against: group.segments
        )

        let basePlan = WorkflowPlan(
            agentKind: representative.agentKind,
            goalPattern: goalPattern,
            steps: steps,
            parameterSlots: parameters.map(\.name),
            successRate: successRate(for: group),
            sourceTraceRefs: sourceTraceRefs(for: group),
            sourceGraphEdgeRefs: sourceGraphEdgeRefs(for: group),
            evidenceTiers: combinedEvidenceTiers(for: group),
            repeatedTraceSegmentCount: group.segments.count,
            replayValidationSuccess: replayValidationSuccess,
            promotionStatus: .candidate,
            lastValidatedAt: Date(),
            lastSucceededAt: latestTimestamp(for: group)
        )

        return WorkflowPlan(
            id: basePlan.id,
            agentKind: basePlan.agentKind,
            goalPattern: basePlan.goalPattern,
            steps: basePlan.steps,
            parameterSlots: basePlan.parameterSlots,
            successRate: basePlan.successRate,
            sourceTraceRefs: basePlan.sourceTraceRefs,
            sourceGraphEdgeRefs: basePlan.sourceGraphEdgeRefs,
            evidenceTiers: basePlan.evidenceTiers,
            repeatedTraceSegmentCount: basePlan.repeatedTraceSegmentCount,
            replayValidationSuccess: basePlan.replayValidationSuccess,
            promotionStatus: promotionPolicy.shouldPromote(basePlan) ? .promoted : .candidate,
            lastValidatedAt: basePlan.lastValidatedAt,
            lastSucceededAt: basePlan.lastSucceededAt
        )
    }

    private func step(from event: TraceEvent) -> WorkflowStep {
        let agentKind = AgentKind(rawValue: event.agentKind ?? AgentKind.os.rawValue) ?? .os
        let semanticQuery: ElementQuery?
        if agentKind == .os {
            semanticQuery = ElementQuery(
                text: event.actionTarget ?? event.selectedElementLabel,
                role: nil,
                editable: event.actionName == "type" || event.actionName == "fill_form",
                clickable: event.actionName == "click" || event.actionName == "read-file",
                visibleOnly: true,
                app: nil
            )
        } else {
            semanticQuery = nil
        }

        let actionContract = ActionContract(
            id: event.actionContractID ?? [
                agentKind.rawValue,
                event.actionName,
                event.workspaceRelativePath ?? event.actionTarget ?? "none",
            ].joined(separator: "|"),
            agentKind: agentKind,
            skillName: event.actionName,
            targetRole: nil,
            targetLabel: event.actionTarget ?? event.selectedElementLabel,
            locatorStrategy: event.selectedElementID == nil ? "query" : "dom-id",
            workspaceRelativePath: event.workspaceRelativePath,
            commandCategory: event.commandCategory,
            plannerFamily: event.plannerFamily
        )

        return WorkflowStep(
            agentKind: agentKind,
            stepPhase: taskPhase(for: event),
            actionContract: actionContract,
            semanticQuery: semanticQuery,
            fromPlanningStateID: event.planningStateID,
            notes: [
                event.postconditionClass.map { "postcondition=\($0)" },
                event.commandSummary,
            ].compactMap { $0 }
        )
    }

    private func successRate(for group: RepeatedTraceSegment) -> Double {
        let totalEvents = group.segments.flatMap(\.events)
        guard !totalEvents.isEmpty else { return 0 }
        let successes = totalEvents.filter(\.success).count
        return Double(successes) / Double(totalEvents.count)
    }

    private func sourceTraceRefs(for group: RepeatedTraceSegment) -> [String] {
        group.segments.flatMap { segment in
            segment.events.map { "\($0.sessionID):\($0.stepID)" }
        }
    }

    private func sourceGraphEdgeRefs(for group: RepeatedTraceSegment) -> [String] {
        Array(
            Set(
                group.segments.flatMap { segment in
                    segment.events.flatMap { event in
                        ([event.currentEdgeID] + (event.pathEdgeIDs ?? [])).compactMap { $0 }
                    }
                }
            )
        ).sorted()
    }

    private func combinedEvidenceTiers(for group: RepeatedTraceSegment) -> [KnowledgeTier] {
        Array(Set(group.segments.flatMap(\.evidenceTiers))).sorted { $0.rawValue < $1.rawValue }
    }

    private func latestTimestamp(for group: RepeatedTraceSegment) -> Date? {
        group.segments.flatMap(\.events).map(\.timestamp).max()
    }

    private func taskPhase(for event: TraceEvent) -> TaskStepPhase {
        switch event.plannerFamily {
        case PlannerFamily.code.rawValue:
            return .engineering
        case PlannerFamily.mixed.rawValue:
            return .handoff
        default:
            return .operatingSystem
        }
    }
}
