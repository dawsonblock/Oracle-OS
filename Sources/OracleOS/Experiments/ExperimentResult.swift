import Foundation

public struct ExperimentResult: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let experimentID: String
    public let candidate: CandidatePatch
    public let sandboxPath: String
    public let commandResults: [CommandResult]
    public let diffSummary: String
    public let architectureRiskScore: Double
    public let architectureFindings: [ArchitectureFinding]
    public let refactorProposalID: String?
    public let selected: Bool

    public init(
        id: String = UUID().uuidString,
        experimentID: String,
        candidate: CandidatePatch,
        sandboxPath: String,
        commandResults: [CommandResult],
        diffSummary: String,
        architectureRiskScore: Double,
        architectureFindings: [ArchitectureFinding] = [],
        refactorProposalID: String? = nil,
        selected: Bool = false
    ) {
        self.id = id
        self.experimentID = experimentID
        self.candidate = candidate
        self.sandboxPath = sandboxPath
        self.commandResults = commandResults
        self.diffSummary = diffSummary
        self.architectureRiskScore = architectureRiskScore
        self.architectureFindings = architectureFindings
        self.refactorProposalID = refactorProposalID
        self.selected = selected
    }

    public var succeeded: Bool {
        commandResults.allSatisfy(\.succeeded)
    }

    public var elapsedMs: Double {
        commandResults.reduce(0) { $0 + $1.elapsedMs }
    }
}
