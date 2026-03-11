import Foundation

public struct InvariantChecker: Sendable {
    public init() {}

    public func findings(
        goalDescription: String,
        affectedModules: [String]
    ) -> [ArchitectureFinding] {
        var findings: [ArchitectureFinding] = []
        let moduleSet = Set(affectedModules)

        if moduleSet.contains("Agent/Planning"), moduleSet.contains("Core/Execution") {
            findings.append(
                ArchitectureFinding(
                    title: "Planning/execution boundary drift",
                    summary: "Changes touch both planning and execution layers. Keep execution semantics out of planner code.",
                    severity: .critical,
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["planner", "executor"],
                    riskScore: 0.85
                )
            )
        }

        if moduleSet.contains("Runtime"), moduleSet.contains("Core/Execution"), goalDescription.lowercased().contains("policy") {
            findings.append(
                ArchitectureFinding(
                    title: "Policy/execution boundary drift",
                    summary: "Policy changes are crossing into execution internals. Keep policy enforcement in runtime/loop layers.",
                    severity: .warning,
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["runtime", "executor", "policy"],
                    riskScore: 0.7
                )
            )
        }

        if moduleSet.contains("Agent/Skills"), moduleSet.contains("Core/Ranking"), goalDescription.lowercased().contains("click") {
            findings.append(
                ArchitectureFinding(
                    title: "Skill/ranking integrity check",
                    summary: "Target-bearing skills must continue to resolve through ranking instead of direct element selection.",
                    severity: .warning,
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["skills", "ranking"],
                    riskScore: 0.65
                )
            )
        }

        return findings
    }
}
