import Foundation

/// Categorizes operators into families that strategies can allow or deny.
///
/// Each ``StrategyKind`` maps to a bounded set of allowed operator families
/// via ``StrategyLibrary``. Plan generation and graph expansion filter
/// candidates against this set, preventing cross-strategy noise.
public enum OperatorFamily: String, Sendable, Codable, CaseIterable {
    case workflow
    case graphEdge = "graph_edge"
    case browserTargeted = "browser_targeted"
    case hostTargeted = "host_targeted"
    case repoAnalysis = "repo_analysis"
    case patchGeneration = "patch_generation"
    case patchExperiment = "patch_experiment"
    case recovery
    case permissionHandling = "permission_handling"
    case exploration
    case llmProposal = "llm_proposal"
}

// MARK: - Operator → OperatorFamily mapping

extension ReasoningOperatorKind {
    /// The operator family this reasoning operator belongs to.
    public var operatorFamily: OperatorFamily {
        switch self {
        case .runTests, .buildProject:
            return .repoAnalysis
        case .applyPatch, .revertPatch, .rollbackPatch:
            return .patchGeneration
        case .rerunTests:
            return .repoAnalysis
        case .dismissModal:
            return .recovery
        case .clickTarget:
            return .browserTargeted
        case .openApplication, .focusWindow, .restartApplication:
            return .hostTargeted
        case .navigateBrowser:
            return .browserTargeted
        case .retryWithAlternateTarget:
            return .recovery
        }
    }
}
