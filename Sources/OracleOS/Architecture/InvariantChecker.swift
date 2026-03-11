import Foundation

public struct InvariantChecker: Sendable {
    public init() {}

    public func report(
        goalDescription: String,
        affectedModules: [String],
        candidatePaths: [String],
        snapshot: RepositorySnapshot
    ) -> GovernanceReport {
        var violations: [GovernanceViolation] = []
        let moduleSet = Set(affectedModules)
        let loweredGoal = goalDescription.lowercased()
        let hasTests = candidatePaths.contains { $0.hasPrefix("Tests/") }

        if moduleSet.contains("Agent/Planning"), moduleSet.contains("Core/Execution") {
            violations.append(
                GovernanceViolation(
                    ruleID: .hierarchicalPlanning,
                    severity: .hardFail,
                    title: "Planning/execution boundary drift",
                    summary: "Changes touch both planning and execution layers. Keep execution semantics out of planner code.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["planner", "executor"]
                )
            )
        }

        if moduleSet.contains("Core/Execution"),
           moduleSet.contains("Core/Policy"),
           !moduleSet.contains("Runtime")
        {
            violations.append(
                GovernanceViolation(
                    ruleID: .executionTruthPath,
                    severity: .hardFail,
                    title: "Execution truth path bypass risk",
                    summary: "Policy changes are reaching execution internals without the runtime boundary in scope.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["policy", "executor"]
                )
            )
        }

        if moduleSet.contains("Runtime"), moduleSet.contains("Core/Execution"), loweredGoal.contains("policy") {
            violations.append(
                GovernanceViolation(
                    ruleID: .executionTruthPath,
                    severity: .advisory,
                    title: "Policy/execution boundary drift",
                    summary: "Policy changes are crossing into execution internals. Keep policy enforcement in runtime/loop layers.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["runtime", "executor", "policy"]
                )
            )
        }

        let touchesTargetBearingSkill = candidatePaths.contains { path in
            path.contains("Agent/Skills/OS/ClickSkill.swift")
                || path.contains("Agent/Skills/OS/TypeSkill.swift")
        }
        let touchesRankingPath = candidatePaths.contains { path in
            path.contains("Core/Ranking/")
                || path.contains("Core/World/WorldQuery.swift")
        }
        if touchesTargetBearingSkill, !touchesRankingPath {
            violations.append(
                GovernanceViolation(
                    ruleID: .hierarchicalPlanning,
                    severity: .hardFail,
                    title: "Target resolution bypass risk",
                    summary: "Target-bearing OS skills changed without ranking or world-query changes in scope. Ranking bypass is not allowed.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        } else if moduleSet.contains("Agent/Skills"), moduleSet.contains("Core/Ranking"), loweredGoal.contains("click") {
            violations.append(
                GovernanceViolation(
                    ruleID: .hierarchicalPlanning,
                    severity: .advisory,
                    title: "Skill/ranking integrity check",
                    summary: "Target-bearing skills must continue to resolve through ranking instead of direct element selection.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["skills", "ranking"]
                )
            )
        }

        if (moduleSet.contains("Graph"), moduleSet.contains("Experiments")) == (true, true)
            || (moduleSet.contains("Graph"), moduleSet.contains("Agent/Recovery")) == (true, true)
        {
            violations.append(
                GovernanceViolation(
                    ruleID: .reusableKnowledge,
                    severity: .hardFail,
                    title: "Trust-tier promotion drift",
                    summary: "Experiment or recovery changes are touching graph persistence paths. Keep evidence tiers separated from stable control knowledge.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

        if moduleSet.contains("Agent/Recovery"),
           !moduleSet.contains("Runtime"),
           !moduleSet.contains("Graph")
        {
            violations.append(
                GovernanceViolation(
                    ruleID: .recoveryMode,
                    severity: .advisory,
                    title: "Recovery path drift",
                    summary: "Recovery logic is changing without runtime or graph tagging in scope. Keep recovery as a first-class tracked mode.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

        if moduleSet.contains("Agent/Recovery"), moduleSet.contains("Graph") {
            violations.append(
                GovernanceViolation(
                    ruleID: .recoveryMode,
                    severity: .hardFail,
                    title: "Recovery tagging must remain explicit",
                    summary: "Recovery code is touching graph behavior directly. Recovery transitions must stay tagged and separate from nominal control knowledge.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

        if ChangeImpactAnalyzer().shouldReview(goalDescription: goalDescription, candidatePaths: candidatePaths), !hasTests {
            violations.append(
                GovernanceViolation(
                    ruleID: .evalBeforeGrowth,
                    severity: .hardFail,
                    title: "Architecture growth without eval coverage",
                    summary: "High-impact architectural work must add or update evals or governance tests in the same change.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

        if !DependencyAnalyzer().findCycles(in: ArchitectureModuleGraph.build(from: snapshot)).isEmpty {
            violations.append(
                GovernanceViolation(
                    ruleID: .evalBeforeGrowth,
                    severity: .advisory,
                    title: "Dependency cycle requires governance follow-up",
                    summary: "Dependency cycles increase architectural risk and should be covered by governance tests or cleanup plans.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["dependency-cycle"]
                )
            )
        }

        return GovernanceReport(violations: violations)
    }
}
