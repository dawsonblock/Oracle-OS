import Foundation
import Testing
@testable import OracleOS

@Suite("Governance Enforcement")
struct GovernanceEnforcementTests {

    @Test("Episode residue is kept out of canonical project memory")
    func episodeResidueIsNotIndexed() throws {
        let projectRoot = makeTempDirectory()
        let store = try ProjectMemoryStore(projectRootURL: projectRoot)

        let ref = try store.writeDraft(
            ProjectMemoryDraft(
                kind: .openProblem,
                knowledgeClass: .episode,
                title: "One-off flaky timeout",
                summary: "Transient CI timeout during one run.",
                affectedModules: ["Tests/OracleOSEvals"],
                evidenceRefs: ["trace:timeout-1"],
                sourceTraceIDs: ["trace-timeout-1"],
                body: "This was a one-off timeout and should stay trace-local."
            )
        )

        let indexed = store.query(text: "flaky timeout")

        #expect(indexed.isEmpty)
        #expect(ref.knowledgeClass == .episode)
        #expect(ref.path.contains("/.oracle/project-memory-episode/"))
        #expect(FileManager.default.fileExists(atPath: ref.path))
    }

    @Test("Direct stable transition recording is sanitized to candidate knowledge")
    func directStableRecordingIsSanitized() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let fromState = planningState(id: "os|finder|browse", taskPhase: "browse")
        let toState = planningState(id: "os|finder|rename", taskPhase: "rename")
        let contract = ActionContract(
            id: "click|AXButton|Rename|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Rename",
            locatorStrategy: "query"
        )

        store.recordTransition(
            VerifiedTransition(
                fromPlanningStateID: fromState.id,
                toPlanningStateID: toState.id,
                actionContractID: contract.id,
                postconditionClass: .focusChanged,
                verified: true,
                failureClass: nil,
                latencyMs: 50,
                knowledgeTier: .stable
            ),
            actionContract: contract,
            fromState: fromState,
            toState: toState
        )

        #expect(store.allStableEdges().isEmpty)
        #expect(store.allCandidateEdges().first?.knowledgeTier == .candidate)
    }

    @Test("Recovery-tagged transitions cannot be recorded as stable knowledge")
    func recoveryKnowledgeIsForcedToRecoveryTier() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let state = planningState(id: "os|chrome|modal", taskPhase: "modal")
        let contract = ActionContract(
            id: "click|AXButton|Dismiss|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Dismiss",
            locatorStrategy: "query"
        )

        store.recordTransition(
            VerifiedTransition(
                fromPlanningStateID: state.id,
                toPlanningStateID: state.id,
                actionContractID: contract.id,
                postconditionClass: .elementDisappeared,
                verified: true,
                failureClass: nil,
                latencyMs: 30,
                recoveryTagged: true,
                knowledgeTier: .stable
            ),
            actionContract: contract,
            fromState: state,
            toState: state
        )

        #expect(store.allStableEdges().isEmpty)
        #expect(store.allCandidateEdges().first?.knowledgeTier == .recovery)
    }

    @Test("Architecture-expanding changes without eval coverage produce a hard governance failure")
    func architectureGrowthRequiresCoverage() {
        let engine = ArchitectureEngine()
        let snapshot = RepositorySnapshot(
            id: "governance-review",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/OracleOS/Runtime/OracleRuntime.swift", isDirectory: false),
                RepositoryFile(path: "Sources/OracleOS/Graph/GraphStore.swift", isDirectory: false),
                RepositoryFile(path: "Tests/OracleOSEvals/OracleOSEvals.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: true
        )

        let review = engine.review(
            goalDescription: "refactor runtime graph boundary",
            snapshot: snapshot,
            candidatePaths: [
                "Sources/OracleOS/Runtime/OracleRuntime.swift",
                "Sources/OracleOS/Graph/GraphStore.swift",
            ]
        )

        #expect(review.governanceReport.isBlocking)
        #expect(review.governanceReport.hardFailures.contains(where: { $0.ruleID == .evalBeforeGrowth }))
    }

    @Test("Workspace runner blocks unsupported arbitrary shell execution")
    func workspaceRunnerBlocksArbitraryShellExecution() throws {
        let root = makeTempDirectory()
        let runner = WorkspaceRunner()
        let spec = CommandSpec(
            category: .build,
            executable: "/bin/sh",
            arguments: ["-c", "echo unsafe"],
            workspaceRoot: root.path,
            summary: "arbitrary shell build"
        )

        #expect(throws: WorkspaceRunnerError.unsupportedCommand(spec.summary)) {
            try runner.execute(spec: spec)
        }
    }

    private func planningState(id: String, taskPhase: String) -> PlanningState {
        PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: id),
            appID: "TestApp",
            domain: nil,
            windowClass: nil,
            taskPhase: taskPhase,
            focusedRole: nil,
            modalClass: nil,
            navigationClass: "governance",
            controlContext: nil
        )
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempGraphURL() -> URL {
        makeTempDirectory().appendingPathComponent("graph.sqlite3", isDirectory: false)
    }
}
