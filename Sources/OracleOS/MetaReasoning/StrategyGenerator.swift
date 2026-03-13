import Foundation

public struct ImprovementCandidate: Sendable {
    public let kind: ImprovementKind
    public let description: String
    public let expectedBenefit: Double
    public let confidence: Double
    public let risk: String
    public let notes: [String]

    public init(
        kind: ImprovementKind,
        description: String,
        expectedBenefit: Double,
        confidence: Double = 0.5,
        risk: String = "low",
        notes: [String] = []
    ) {
        self.kind = kind
        self.description = description
        self.expectedBenefit = expectedBenefit
        self.confidence = confidence
        self.risk = risk
        self.notes = notes
    }
}

public enum ImprovementKind: String, Sendable {
    case newWorkflow = "new_workflow"
    case newPatchStrategy = "new_patch_strategy"
    case newRecoveryTactic = "new_recovery_tactic"
    case plannerHeuristic = "planner_heuristic"
    case memoryPattern = "memory_pattern"
}

public final class StrategyGenerator: @unchecked Sendable {
    private let llmClient: LLMClient?

    public init(llmClient: LLMClient? = nil) {
        self.llmClient = llmClient
    }

    public func generate(from report: PerformanceReport) async -> [ImprovementCandidate] {
        var candidates: [ImprovementCandidate] = []

        candidates.append(contentsOf: deterministicImprovements(from: report))

        if let llmClient {
            let llmCandidates = await llmImprovements(from: report, llmClient: llmClient)
            candidates.append(contentsOf: llmCandidates)
        }

        return candidates.sorted { $0.expectedBenefit > $1.expectedBenefit }
    }

    private func deterministicImprovements(from report: PerformanceReport) -> [ImprovementCandidate] {
        var candidates: [ImprovementCandidate] = []

        if report.outcome == .success && report.recoveryCount == 0 {
            candidates.append(ImprovementCandidate(
                kind: .newWorkflow,
                description: "Promote successful trace to workflow candidate",
                expectedBenefit: 0.6,
                confidence: 0.7,
                notes: ["task \(report.taskID) completed cleanly"]
            ))
        }

        let effectiveStrategies = report.strategyEffectiveness
            .filter { $0.wasEffective && $0.contributionScore > 0.7 }
        for strategy in effectiveStrategies {
            candidates.append(ImprovementCandidate(
                kind: .memoryPattern,
                description: "Reinforce high-performing strategy: \(strategy.strategyName)",
                expectedBenefit: strategy.contributionScore * 0.5,
                confidence: strategy.contributionScore,
                notes: strategy.notes
            ))
        }

        if report.recoveryCount > 2 {
            candidates.append(ImprovementCandidate(
                kind: .newRecoveryTactic,
                description: "Improve recovery strategy selection for tasks with high recovery count",
                expectedBenefit: 0.4,
                confidence: 0.5,
                risk: "medium",
                notes: ["\(report.recoveryCount) recoveries during task"]
            ))
        }

        for bottleneck in report.bottlenecks {
            candidates.append(ImprovementCandidate(
                kind: .plannerHeuristic,
                description: "Address bottleneck: \(bottleneck)",
                expectedBenefit: 0.35,
                confidence: 0.4,
                risk: "medium",
                notes: ["detected during task \(report.taskID)"]
            ))
        }

        return candidates
    }

    private func llmImprovements(
        from report: PerformanceReport,
        llmClient: LLMClient
    ) async -> [ImprovementCandidate] {
        let prompt = buildImprovementPrompt(from: report)
        let request = LLMRequest(
            prompt: prompt,
            modelTier: .metaReasoning,
            maxTokens: 512
        )

        do {
            let response = try await llmClient.complete(request)
            return parseImprovements(from: response.text)
        } catch {
            return []
        }
    }

    private func buildImprovementPrompt(from report: PerformanceReport) -> String {
        var lines: [String] = []
        lines.append("Analyze the task execution.")
        lines.append("")
        lines.append("Task: \(report.taskID)")
        lines.append("Outcome: \(report.outcome.rawValue)")
        lines.append("Recovery count: \(report.recoveryCount)")
        lines.append("")
        if !report.bottlenecks.isEmpty {
            lines.append("Bottlenecks:")
            for b in report.bottlenecks { lines.append("- \(b)") }
        }
        if !report.failureCauses.isEmpty {
            lines.append("Failure causes:")
            for c in report.failureCauses { lines.append("- \(c)") }
        }
        lines.append("")
        lines.append("Suggest improved strategies for similar tasks.")
        return lines.joined(separator: "\n")
    }

    private func parseImprovements(from text: String) -> [ImprovementCandidate] {
        var candidates: [ImprovementCandidate] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("strategy:") || trimmed.lowercased().hasPrefix("- ") else {
                continue
            }
            let description = trimmed
                .replacingOccurrences(of: "strategy:", with: "")
                .replacingOccurrences(of: "- ", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !description.isEmpty else { continue }
            candidates.append(ImprovementCandidate(
                kind: .plannerHeuristic,
                description: description,
                expectedBenefit: 0.3,
                confidence: 0.4,
                notes: ["LLM-suggested improvement"]
            ))
        }
        return candidates
    }
}
