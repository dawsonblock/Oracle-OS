import Foundation

public final class ParallelRunner: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner

    public init(workspaceRunner: WorkspaceRunner = WorkspaceRunner()) {
        self.workspaceRunner = workspaceRunner
    }

    public func run(
        spec: ExperimentSpec,
        experimentsRoot: URL,
        architectureRiskScore: Double
    ) async throws -> [ExperimentResult] {
        let workspaceRoot = URL(fileURLWithPath: spec.workspaceRoot, isDirectory: true)
        let workspaceRunner = self.workspaceRunner

        return try await withThrowingTaskGroup(of: ExperimentResult.self) { group in
            for candidate in spec.candidates {
                group.addTask {
                    let sandbox = try WorktreeSandbox.create(
                        experimentID: spec.id,
                        candidateID: candidate.id,
                        workspaceRoot: workspaceRoot,
                        experimentsRoot: experimentsRoot
                    )
                    try sandbox.apply(candidate)

                    var results: [CommandResult] = []
                    let buildTool = BuildToolDetector.detect(at: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true))
                    let buildCommand = spec.buildCommand.map {
                        CommandSpec(
                            category: $0.category,
                            executable: $0.executable,
                            arguments: $0.arguments,
                            workspaceRoot: sandbox.sandboxPath,
                            workspaceRelativePath: $0.workspaceRelativePath,
                            summary: $0.summary,
                            mutatesWorkspace: $0.mutatesWorkspace,
                            touchesNetwork: $0.touchesNetwork
                        )
                    } ?? BuildToolDetector.defaultBuildCommand(
                        for: buildTool,
                        workspaceRoot: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)
                    )
                    let testCommand = spec.testCommand.map {
                        CommandSpec(
                            category: $0.category,
                            executable: $0.executable,
                            arguments: $0.arguments,
                            workspaceRoot: sandbox.sandboxPath,
                            workspaceRelativePath: $0.workspaceRelativePath,
                            summary: $0.summary,
                            mutatesWorkspace: $0.mutatesWorkspace,
                            touchesNetwork: $0.touchesNetwork
                        )
                    } ?? BuildToolDetector.defaultTestCommand(
                        for: buildTool,
                        workspaceRoot: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)
                    )

                    if let buildCommand {
                        results.append(try workspaceRunner.execute(spec: buildCommand))
                    }
                    if results.allSatisfy(\.succeeded), let testCommand {
                        results.append(try workspaceRunner.execute(spec: testCommand))
                    }

                    return ExperimentResult(
                        experimentID: spec.id,
                        candidate: candidate,
                        sandboxPath: sandbox.sandboxPath,
                        commandResults: results,
                        diffSummary: sandbox.diffSummary(),
                        architectureRiskScore: architectureRiskScore
                    )
                }
            }

            var collected: [ExperimentResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
    }
}
