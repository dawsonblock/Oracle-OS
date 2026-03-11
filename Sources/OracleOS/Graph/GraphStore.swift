import Foundation

public final class GraphStore {
    private let candidateGraph: CandidateGraph
    private let stableGraph: StableGraph
    private var actionContracts: [String: ActionContract]

    public init(
        candidateGraph: CandidateGraph = CandidateGraph(),
        stableGraph: StableGraph = StableGraph(),
        actionContracts: [String: ActionContract] = [:]
    ) {
        self.candidateGraph = candidateGraph
        self.stableGraph = stableGraph
        self.actionContracts = actionContracts
    }

    public func recordTransition(
        _ transition: VerifiedTransition,
        actionContract: ActionContract? = nil
    ) {
        candidateGraph.record(transition)
        if let actionContract {
            actionContracts[actionContract.id] = actionContract
        }
    }

    public func promoteStableGraph() {
        stableGraph.promote(from: candidateGraph)
    }

    public func outgoingEdges(from planningStateID: PlanningStateID) -> [EdgeTransition] {
        stableGraph.outgoing(from: planningStateID)
    }

    public func actionContract(for id: String) -> ActionContract? {
        actionContracts[id]
    }
}
