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

    @Test("OS recovery eval formalizes ambiguous-step recovery metrics")
    func osRecoveryEval() async {
        let metrics = await EvalRunner.run(task: makeOSRecoveryTask())
        #expect(metrics.successRate == 1)
        #expect(metrics.recoveryRate > 0)
    }

    @Test("Code eval formalizes bounded edit build test repair metrics")
    func codeRepairEval() async {
        let metrics = await EvalRunner.run(task: makeCodeRepairTask())
        #expect(metrics.successRate == 1)
        #expect(metrics.averageSteps >= 1)
        #expect(metrics.patchSelectionSuccessRate == 1)
    }

    @Test("Hybrid eval formalizes OS handoff into code execution")
    func hybridRepoEval() async {
        let metrics = await EvalRunner.run(task: makeHybridRepoTask())
        #expect(metrics.successRate == 1)
        #expect(metrics.averageSteps >= 2)
        #expect(metrics.patchSelectionSuccessRate == 1)
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

    private func makeOSRecoveryTask() -> EvalTask {
        EvalTask(name: "os-recovery", runs: 3) { _ in
            let ambiguous = Observation(
                app: "Finder",
                windowTitle: "Finder",
                url: nil,
                focusedElementID: "rename-primary",
                elements: [
                    UnifiedElement(id: "rename-primary", source: .ax, role: "AXButton", label: "Rename", focused: true, confidence: 0.95),
                    UnifiedElement(id: "rename-secondary", source: .ax, role: "AXButton", label: "Rename", confidence: 0.94),
                ]
            )
            let resolved = Observation(
                app: "Finder",
                windowTitle: "Finder",
                url: nil,
                focusedElementID: "save",
                elements: [
                    UnifiedElement(id: "save", source: .ax, role: "AXButton", label: "Save", focused: true, confidence: 0.97),
                ]
            )
            let loop = AgentLoop(
                observationProvider: EvalObservationProvider([ambiguous, resolved]),
                executionDriver: EvalExecutionDriver { _, decision, _ in
                    EvalExecutionDriver.recordedSources.append(decision.source)
                    return ToolResult(success: true, data: [
                        "action_result": ActionResult(success: true, verified: true).toDict(),
                    ])
                },
                planner: Planner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: AppMemoryStore()
            )
            EvalExecutionDriver.recordedSources = []
            let outcome = await loop.run(
                goal: Goal(
                    description: "rename file in finder",
                    targetApp: "Finder",
                    targetTaskPhase: "save"
                )
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph)
            )
        }
    }

    private func makeCodeRepairTask() -> EvalTask {
        EvalTask(name: "code-repair", runs: 1) { _ in
            let workspace = try! makeBrokenSwiftWorkspace()
            let provider = EvalObservationProvider([
                Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            ])
            let driver = EvalExecutionDriver { intent, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                EvalExecutionDriver.selectedExperimentReplay = EvalExecutionDriver.selectedExperimentReplay || (decision.selectedExperimentCandidate == true)
                if intent.agentKind == .code,
                   let root = intent.workspaceRoot,
                   let relativePath = intent.workspaceRelativePath,
                   let text = intent.text
                {
                    let fileURL = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(relativePath)
                    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? text.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            EvalExecutionDriver.selectedExperimentReplay = false
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                planner: Planner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: AppMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(
                    description: "fix failing swift build",
                    targetTaskPhase: "code-clean",
                    workspaceRoot: workspace.root.path,
                    preferredAgentKind: .code,
                    experimentCandidates: workspace.candidates
                )
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                patchSelectionSucceeded: EvalExecutionDriver.selectedExperimentReplay
            )
        }
    }

    private func makeHybridRepoTask() -> EvalTask {
        EvalTask(name: "hybrid-repo", runs: 1) { _ in
            let workspace = try! makeBrokenSwiftWorkspace()
            let provider = EvalObservationProvider([
                Observation(app: "Notes", windowTitle: "Notes", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Finder", windowTitle: "Finder", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Finder", windowTitle: "Finder", url: nil, focusedElementID: nil, elements: []),
            ])
            let driver = EvalExecutionDriver { intent, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                EvalExecutionDriver.selectedExperimentReplay = EvalExecutionDriver.selectedExperimentReplay || (decision.selectedExperimentCandidate == true)
                if intent.agentKind == .code,
                   let root = intent.workspaceRoot,
                   let relativePath = intent.workspaceRelativePath,
                   let text = intent.text
                {
                    let fileURL = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(relativePath)
                    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? text.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            EvalExecutionDriver.selectedExperimentReplay = false
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                planner: Planner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: AppMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(
                    description: "open repo in finder then fix failing swift build",
                    targetTaskPhase: "code-clean",
                    workspaceRoot: workspace.root.path,
                    preferredAgentKind: .mixed,
                    experimentCandidates: workspace.candidates
                )
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                patchSelectionSucceeded: EvalExecutionDriver.selectedExperimentReplay
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
    static var selectedExperimentReplay = false

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

private struct BrokenSwiftWorkspace {
    let root: URL
    let candidates: [CandidatePatch]
}

private func makeBrokenSwiftWorkspace() throws -> BrokenSwiftWorkspace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sources = root.appendingPathComponent("Sources/Example", isDirectory: true)
    let tests = root.appendingPathComponent("Tests/ExampleTests", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

    let package = """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "Example",
        products: [
            .library(name: "Example", targets: ["Example"]),
        ],
        targets: [
            .target(name: "Example"),
            .testTarget(name: "ExampleTests", dependencies: ["Example"]),
        ]
    )
    """

    let goodSource = """
    public struct Calculator {
        public static func double(_ value: Int) -> Int {
            value * 2
        }
    }
    """

    let brokenSource = """
    public struct Calculator {
        public static func double(_ value: Int) -> Int {
            value *
        }
    }
    """

    let failingTestSource = """
    public struct Calculator {
        public static func double(_ value: Int) -> Int {
            value * 3
        }
    }
    """

    let testSource = """
    import Testing
    @testable import Example

    @Test func doublesInput() {
        #expect(Calculator.double(2) == 4)
    }
    """
    let gitignore = """
    .oracle/
    """

    try package.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    try gitignore.write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    try goodSource.write(to: sources.appendingPathComponent("Calculator.swift"), atomically: true, encoding: .utf8)
    try testSource.write(to: tests.appendingPathComponent("CalculatorTests.swift"), atomically: true, encoding: .utf8)

    try runProcess(["git", "init"], cwd: root)
    try runProcess(["git", "config", "user.email", "eval@example.com"], cwd: root)
    try runProcess(["git", "config", "user.name", "Eval Runner"], cwd: root)
    try runProcess(["git", "add", "."], cwd: root)
    try runProcess(["git", "commit", "-m", "baseline"], cwd: root)

    try brokenSource.write(to: sources.appendingPathComponent("Calculator.swift"), atomically: true, encoding: .utf8)

    return BrokenSwiftWorkspace(
        root: root,
        candidates: [
            CandidatePatch(
                title: "Restore valid calculator implementation",
                summary: "Restore the known-good implementation so build and tests pass.",
                workspaceRelativePath: "Sources/Example/Calculator.swift",
                content: goodSource,
                hypothesis: "Revert the broken edit."
            ),
            CandidatePatch(
                title: "Replace build failure with test failure",
                summary: "Compiles but keeps the task failing under tests.",
                workspaceRelativePath: "Sources/Example/Calculator.swift",
                content: failingTestSource,
                hypothesis: "Compile first, then inspect test failure."
            ),
        ]
    )
}

private func runProcess(_ arguments: [String], cwd: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = cwd
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "process failed"
        throw NSError(domain: "OracleOSEvals", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }
}
