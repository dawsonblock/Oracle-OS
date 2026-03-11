import Foundation
import Testing
@testable import OracleOS

@Suite("Digital Engineer Layer")
struct DigitalEngineerLayerTests {

    @Test("Project memory drafts are indexed and retrieved by goal and module")
    func projectMemoryDraftsAreQueryable() throws {
        let projectRoot = makeTempDirectory()
        let store = try ProjectMemoryStore(projectRootURL: projectRoot)

        let draftRef = try store.writeArchitectureDecisionDraft(
            title: "Use graph-backed planner",
            summary: "Prefer verified transitions over direct planner heuristics.",
            affectedModules: ["Agent/Planning", "Graph"],
            evidenceRefs: ["trace:graph-backed-loop"],
            sourceTraceIDs: ["trace-graph-1"],
            body: "Decision: use graph-backed planning to keep execution reusable and safe."
        )

        let snapshot = RepositorySnapshot(
            id: "repo-snapshot",
            workspaceRoot: projectRoot.path,
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/OracleOS/Agent/Planning/Planner.swift", isDirectory: false),
                RepositoryFile(path: "Sources/OracleOS/Graph/GraphStore.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: false
        )

        let refs = ProjectMemoryQuery.relevantRecords(
            goalDescription: "graph-backed planner",
            snapshot: snapshot,
            store: store
        )

        #expect(refs.contains(where: { $0.id == draftRef.id }))
        #expect(refs.contains(where: { $0.affectedModules.contains("Agent/Planning") }))
    }

    @Test("Architecture engine emits cycle and boundary findings")
    func architectureEngineEmitsFindings() {
        let engine = ArchitectureEngine()
        let snapshot = RepositorySnapshot(
            id: "architecture-review",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/OracleOS/Agent/Planning/Planner.swift", isDirectory: false),
                RepositoryFile(path: "Sources/OracleOS/Core/Execution/VerifiedActionExecutor.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(edges: [
                DependencyEdge(
                    sourcePath: "Sources/OracleOS/Agent/Planning/Planner.swift",
                    dependency: "Sources/OracleOS/Core/Execution/VerifiedActionExecutor.swift"
                ),
                DependencyEdge(
                    sourcePath: "Sources/OracleOS/Core/Execution/VerifiedActionExecutor.swift",
                    dependency: "Sources/OracleOS/Agent/Planning/Planner.swift"
                ),
            ]),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: true
        )

        let review = engine.review(
            goalDescription: "refactor planner and execution boundary",
            snapshot: snapshot,
            candidatePaths: [
                "Sources/OracleOS/Agent/Planning/Planner.swift",
                "Sources/OracleOS/Core/Execution/VerifiedActionExecutor.swift",
            ]
        )

        #expect(review.triggered)
        #expect(review.findings.contains(where: { $0.title == "Dependency cycle detected" }))
        #expect(review.findings.contains(where: { $0.title == "Planning/execution boundary drift" }))
        #expect(review.refactorProposal != nil)
        let affectedModules = review.refactorProposal?.affectedModules ?? []
        #expect(affectedModules.contains("Agent/Planning"))
    }

    @Test("Experiment manager isolates candidate worktrees and keeps main workspace unchanged")
    func experimentManagerIsolatesCandidates() async throws {
        let workspaceRoot = try makeCommittedGitWorkspace()
        let filePath = workspaceRoot.appendingPathComponent("Sources/Parser.swift", isDirectory: false)
        let baseline = try String(contentsOf: filePath, encoding: .utf8)

        let spec = ExperimentSpec(
            id: "parser-fix",
            goalDescription: "fix parser edge case",
            workspaceRoot: workspaceRoot.path,
            candidates: [
                CandidatePatch(
                    id: "minimal",
                    title: "Minimal parser fix",
                    summary: "Adjust one branch condition.",
                    workspaceRelativePath: "Sources/Parser.swift",
                    content: "struct Parser {\n    let mode = 2\n}\n"
                ),
                CandidatePatch(
                    id: "rewrite",
                    title: "Tokenizer rewrite",
                    summary: "Rewrite parser branch with more changes.",
                    workspaceRelativePath: "Sources/Parser.swift",
                    content: "struct Parser {\n    let mode = 2\n    let normalize = true\n    func parse() -> Int {\n        mode + (normalize ? 1 : 0)\n    }\n}\n"
                ),
                CandidatePatch(
                    id: "normalization",
                    title: "Normalization fix",
                    summary: "Add normalization helper before parse.",
                    workspaceRelativePath: "Sources/Parser.swift",
                    content: "struct Parser {\n    let mode = 2\n    func normalized() -> Int {\n        mode + 1\n    }\n\n    func parse() -> Int {\n        normalized()\n    }\n}\n"
                ),
            ]
        )

        let manager = ExperimentManager()
        let results = try await manager.run(spec: spec, architectureRiskScore: 0.2)

        #expect(results.count == 3)
        let selectedResults = results.filter { $0.selected }
        #expect(selectedResults.count == 1)
        let allSucceeded = results.allSatisfy { $0.succeeded }
        #expect(allSucceeded)

        let selected = try #require(selectedResults.first)
        let replay = manager.replaySelected(from: results)

        #expect(replay?.id == selected.candidate.id)
        #expect(FileManager.default.fileExists(atPath: selected.sandboxPath))
        #expect((try String(contentsOf: filePath, encoding: .utf8)) == baseline)
    }

    @Test("Experiment results rank smaller passing patches ahead of larger ones")
    func experimentResultsRankCorrectly() {
        let comparator = ResultComparator()
        let workspaceRoot = "/tmp/workspace"
        let minimal = ExperimentResult(
            experimentID: "exp-1",
            candidate: CandidatePatch(
                id: "minimal",
                title: "Minimal",
                summary: "Small fix",
                workspaceRelativePath: "Sources/Parser.swift",
                content: "let a = 1\n"
            ),
            sandboxPath: "/tmp/minimal",
            commandResults: [
                CommandResult(
                    succeeded: true,
                    exitCode: 0,
                    stdout: "",
                    stderr: "",
                    elapsedMs: 25,
                    workspaceRoot: workspaceRoot,
                    category: .test,
                    summary: "swift test"
                ),
            ],
            diffSummary: " Sources/Parser.swift | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)",
            architectureRiskScore: 0.2
        )
        let rewrite = ExperimentResult(
            experimentID: "exp-1",
            candidate: CandidatePatch(
                id: "rewrite",
                title: "Rewrite",
                summary: "Large fix",
                workspaceRelativePath: "Sources/Parser.swift",
                content: "let a = 2\nlet b = 3\nlet c = 4\n"
            ),
            sandboxPath: "/tmp/rewrite",
            commandResults: [
                CommandResult(
                    succeeded: true,
                    exitCode: 0,
                    stdout: "",
                    stderr: "",
                    elapsedMs: 30,
                    workspaceRoot: workspaceRoot,
                    category: .test,
                    summary: "swift test"
                ),
            ],
            diffSummary: " Sources/Parser.swift | 8 +++++---\n 1 file changed, 5 insertions(+), 3 deletions(-)",
            architectureRiskScore: 0.2
        )

        let ranked = comparator.sort([rewrite, minimal])

        #expect(ranked.first?.candidate.id == "minimal")
    }

    @Test("Experiment knowledge tier does not promote directly to stable graph")
    func experimentTierDoesNotPromoteDirectly() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let fromState = planningState(id: "code|build-failing", taskPhase: "build-failing")
        let toState = planningState(id: "code|build-passing", taskPhase: "build-passing")
        let contract = ActionContract(
            id: "code|edit_file|Package.swift|Sources/Parser.swift",
            agentKind: .code,
            skillName: "edit_file",
            targetRole: nil,
            targetLabel: nil,
            locatorStrategy: "code-planner",
            workspaceRelativePath: "Sources/Parser.swift",
            commandCategory: CodeCommandCategory.editFile.rawValue,
            plannerFamily: PlannerFamily.code.rawValue
        )

        for _ in 0..<5 {
            store.recordTransition(
                VerifiedTransition(
                    fromPlanningStateID: fromState.id,
                    toPlanningStateID: toState.id,
                    actionContractID: contract.id,
                    agentKind: .code,
                    workspaceRelativePath: "Sources/Parser.swift",
                    commandCategory: CodeCommandCategory.editFile.rawValue,
                    plannerFamily: PlannerFamily.code.rawValue,
                    postconditionClass: .textChanged,
                    verified: true,
                    failureClass: nil,
                    latencyMs: 100,
                    knowledgeTier: .experiment
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }

        let promoted = store.promoteEligibleEdges()

        #expect(promoted.isEmpty)
        #expect(store.allStableEdges().isEmpty)
        #expect(store.allCandidateEdges().first?.knowledgeTier == .experiment)
    }

    private func planningState(id: String, taskPhase: String) -> PlanningState {
        PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: id),
            appID: "Workspace",
            domain: nil,
            windowClass: nil,
            taskPhase: taskPhase,
            focusedRole: nil,
            modalClass: nil,
            navigationClass: "code",
            controlContext: nil
        )
    }

    private func makeTempGraphURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("graph.sqlite3", isDirectory: false)
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeCommittedGitWorkspace() throws -> URL {
        let root = makeTempDirectory()
        let sourceDir = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("Parser.swift", isDirectory: false)
        try "struct Parser {\n    let mode = 1\n}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "codex@example.com"], in: root)
        try runGit(["config", "user.name", "Codex"], in: root)
        try runGit(["add", "."], in: root)
        try runGit(["commit", "-m", "Initial commit"], in: root)

        return root
    }

    private func runGit(_ arguments: [String], in root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = root
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw NSError(
                domain: "DigitalEngineerLayerTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
    }
}
