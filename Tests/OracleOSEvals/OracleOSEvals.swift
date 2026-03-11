import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Oracle OS Evals")
struct OracleOSEvals {

    @Test("Finder rename eval reports repeated task metrics")
    func finderRenameEval() async {
        let metrics = await EvalRunner.run(task: makeFinderRenameTask())
        #expect(metrics.successRate == 1)
        #expect(metrics.averageSteps >= 1)
        #expect(metrics.graphReuseRatio == 0)
    }

    @Test("Chrome navigation eval uses stable graph path")
    func chromeNavigationEval() async {
        let metrics = await EvalRunner.run(task: makeChromeNavigationTask())
        #expect(metrics.successRate == 1)
        #expect(metrics.graphReuseRatio == 1)
        #expect(metrics.ambiguityFailureCount == 0)
    }

    @Test("Gmail compose eval tracks recoveries and graph reuse")
    func gmailComposeEval() async {
        let metrics = await EvalRunner.run(task: makeGmailComposeTask())
        #expect(metrics.successRate == 1)
        #expect(metrics.recoveryRate >= 0)
        #expect(metrics.graphReuseRatio == 1)
    }

    private func makeFinderRenameTask() -> EvalTask {
        EvalTask(name: "finder-rename", runs: 3) { _ in
            let abstraction = StateAbstraction()
            let initial = Observation(
                app: "Finder",
                windowTitle: "Finder",
                url: nil,
                focusedElementID: "rename",
                elements: [
                    UnifiedElement(id: "rename", source: .ax, role: "AXButton", label: "Rename", focused: true, confidence: 0.96),
                ]
            )
            let renamed = Observation(
                app: "Finder",
                windowTitle: "Finder",
                url: nil,
                focusedElementID: "save",
                elements: [
                    UnifiedElement(id: "save", source: .ax, role: "AXButton", label: "Save", focused: true, confidence: 0.95),
                ]
            )
            let provider = EvalObservationProvider([initial, renamed])
            let driver = EvalExecutionDriver { _, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                stateAbstraction: abstraction,
                planner: Planner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: AppMemoryStore()
            )
            EvalExecutionDriver.recordedSources = []
            let outcome = await loop.run(
                goal: Goal(description: "rename file in finder", targetApp: "Finder", targetTaskPhase: "save")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph)
            )
        }
    }

    private func makeChromeNavigationTask() -> EvalTask {
        EvalTask(name: "chrome-navigation", runs: 3) { _ in
            let abstraction = StateAbstraction()
            let current = Observation(
                app: "Google Chrome",
                windowTitle: "Search - Google Chrome",
                url: "https://www.google.com",
                focusedElementID: "inbox",
                elements: [
                    UnifiedElement(id: "inbox", source: .ax, role: "AXButton", label: "Inbox", focused: true, confidence: 0.97),
                ]
            )
            let destination = Observation(
                app: "Google Chrome",
                windowTitle: "Inbox - Gmail",
                url: "https://mail.google.com/mail/u/0/#inbox",
                focusedElementID: "compose",
                elements: [
                    UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", focused: true, confidence: 0.97),
                ]
            )
            let fromState = abstraction.abstract(observation: current, observationHash: ObservationHash.hash(current))
            let toState = abstraction.abstract(observation: destination, observationHash: ObservationHash.hash(destination))
            let store = GraphStore(databaseURL: makeTempGraphURL())
            let contract = ActionContract(
                id: "click|AXButton|Inbox|query",
                skillName: "click",
                targetRole: "AXButton",
                targetLabel: "Inbox",
                locatorStrategy: "query"
            )
            for _ in 0..<5 {
                store.recordTransition(
                    VerifiedTransition(
                        fromPlanningStateID: fromState.id,
                        toPlanningStateID: toState.id,
                        actionContractID: contract.id,
                        postconditionClass: .navigationOccurred,
                        verified: true,
                        failureClass: nil,
                        latencyMs: 100
                    ),
                    actionContract: contract,
                    fromState: fromState,
                    toState: toState
                )
            }
            _ = store.promoteEligibleEdges()

            let provider = EvalObservationProvider([current, destination])
            let driver = EvalExecutionDriver { _, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                stateAbstraction: abstraction,
                planner: Planner(),
                graphStore: store,
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: AppMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(description: "open chrome inbox", targetApp: "Google Chrome", targetDomain: "mail.google.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph)
            )
        }
    }

    private func makeGmailComposeTask() -> EvalTask {
        EvalTask(name: "gmail-compose", runs: 3) { _ in
            let abstraction = StateAbstraction()
            let inbox = Observation(
                app: "Google Chrome",
                windowTitle: "Inbox - Gmail",
                url: "https://mail.google.com/mail/u/0/#inbox",
                focusedElementID: "compose",
                elements: [
                    UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", focused: true, confidence: 0.98),
                ]
            )
            let compose = Observation(
                app: "Google Chrome",
                windowTitle: "Compose - Gmail",
                url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
                focusedElementID: "body",
                elements: [
                    UnifiedElement(id: "body", source: .ax, role: "AXTextArea", label: "Message Body", focused: true, confidence: 0.97),
                    UnifiedElement(id: "send", source: .ax, role: "AXButton", label: "Send", confidence: 0.91),
                ]
            )
            let fromState = abstraction.abstract(observation: inbox, observationHash: ObservationHash.hash(inbox))
            let toState = abstraction.abstract(observation: compose, observationHash: ObservationHash.hash(compose))
            let store = GraphStore(databaseURL: makeTempGraphURL())
            let contract = ActionContract(
                id: "click|AXButton|Compose|query",
                skillName: "click",
                targetRole: "AXButton",
                targetLabel: "Compose",
                locatorStrategy: "query"
            )
            for _ in 0..<5 {
                store.recordTransition(
                    VerifiedTransition(
                        fromPlanningStateID: fromState.id,
                        toPlanningStateID: toState.id,
                        actionContractID: contract.id,
                        postconditionClass: .elementAppeared,
                        verified: true,
                        failureClass: nil,
                        latencyMs: 120
                    ),
                    actionContract: contract,
                    fromState: fromState,
                    toState: toState
                )
            }
            _ = store.promoteEligibleEdges()

            let provider = EvalObservationProvider([inbox, compose])
            let driver = EvalExecutionDriver { _, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                stateAbstraction: abstraction,
                planner: Planner(),
                graphStore: store,
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: AppMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(description: "open gmail compose", targetApp: "Google Chrome", targetDomain: "mail.google.com", targetTaskPhase: "compose")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph)
            )
        }
    }

    private func makeTempGraphURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("graph.sqlite3", isDirectory: false)
    }
}

@MainActor
private final class EvalObservationProvider: ObservationProvider {
    private let observations: [Observation]
    private var index = 0

    init(_ observations: [Observation]) {
        self.observations = observations
    }

    func observe() -> Observation {
        let observation = observations[min(index, observations.count - 1)]
        if index < observations.count - 1 {
            index += 1
        }
        return observation
    }
}

@MainActor
private final class EvalExecutionDriver: AgentExecutionDriver {
    static var recordedSources: [PlannerSource] = []

    private let handler: (ActionIntent, PlannerDecision, ElementCandidate?) -> ToolResult

    init(handler: @escaping (ActionIntent, PlannerDecision, ElementCandidate?) -> ToolResult) {
        self.handler = handler
    }

    func execute(
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult {
        handler(intent, plannerDecision, selectedCandidate)
    }
}
