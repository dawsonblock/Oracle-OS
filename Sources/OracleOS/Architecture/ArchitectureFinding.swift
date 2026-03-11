import Foundation

public enum ArchitectureFindingSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

public struct ArchitectureFinding: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let severity: ArchitectureFindingSeverity
    public let affectedModules: [String]
    public let evidence: [String]
    public let riskScore: Double

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        severity: ArchitectureFindingSeverity,
        affectedModules: [String] = [],
        evidence: [String] = [],
        riskScore: Double
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.severity = severity
        self.affectedModules = affectedModules
        self.evidence = evidence
        self.riskScore = riskScore
    }
}

public struct RefactorProposal: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let affectedModules: [String]
    public let steps: [String]
    public let invariantRefs: [String]
    public let riskScore: Double

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        affectedModules: [String],
        steps: [String],
        invariantRefs: [String] = [],
        riskScore: Double
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.affectedModules = affectedModules
        self.steps = steps
        self.invariantRefs = invariantRefs
        self.riskScore = riskScore
    }
}

public struct ArchitectureReview: Codable, Sendable, Equatable {
    public let triggered: Bool
    public let affectedModules: [String]
    public let findings: [ArchitectureFinding]
    public let refactorProposal: RefactorProposal?
    public let riskScore: Double

    public init(
        triggered: Bool,
        affectedModules: [String],
        findings: [ArchitectureFinding],
        refactorProposal: RefactorProposal?,
        riskScore: Double
    ) {
        self.triggered = triggered
        self.affectedModules = affectedModules
        self.findings = findings
        self.refactorProposal = refactorProposal
        self.riskScore = riskScore
    }
}
