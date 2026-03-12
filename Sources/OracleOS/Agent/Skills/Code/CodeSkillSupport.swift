import Foundation

public enum CodeSkillResolutionError: Error, Sendable, Equatable {
    case missingWorkspace
    case noRepositorySnapshot
    case noRelevantFiles(String)
    case ambiguousEditTarget(String)

    public var failureClass: FailureClass {
        switch self {
        case .missingWorkspace:
            return .workspaceScopeViolation
        case .noRepositorySnapshot, .noRelevantFiles:
            return .noRelevantFiles
        case .ambiguousEditTarget:
            return .ambiguousEditTarget
        }
    }
}

enum CodeSkillSupport {
    static func workspaceRoot(taskContext: TaskContext, state: WorldState) throws -> URL {
        if let workspaceRoot = taskContext.workspaceRoot {
            return URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        }
        if let snapshotRoot = state.repositorySnapshot?.workspaceRoot {
            return URL(fileURLWithPath: snapshotRoot, isDirectory: true)
        }
        throw CodeSkillResolutionError.missingWorkspace
    }

    static func repositorySnapshot(state: WorldState, workspaceRoot: URL) throws -> RepositorySnapshot {
        if let repositorySnapshot = state.repositorySnapshot {
            return repositorySnapshot
        }
        return RepositoryIndexer().index(workspaceRoot: workspaceRoot)
    }

    static func preferredPath(
        taskContext: TaskContext,
        state: WorldState,
        memoryStore: AppMemoryStore,
        failureOutput: String? = nil
    ) throws -> String {
        let workspaceRoot = try workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: state,
                errorSignature: failureOutput
            )
        )

        if let preferredPath = memoryInfluence.preferredFixPath {
            return preferredPath
        }

        var matches: [String] = []
        if let failureOutput, !failureOutput.isEmpty {
            matches = RepositoryQuery.likelyFiles(for: failureOutput, in: snapshot)
        }

        if matches.isEmpty {
            matches = snapshot.files
                .filter { !$0.isDirectory && ($0.path.hasSuffix(".swift") || $0.path.hasSuffix(".ts") || $0.path.hasSuffix(".js")) }
                .map(\.path)
        }

        guard let first = matches.first else {
            throw CodeSkillResolutionError.noRelevantFiles(taskContext.goal.description)
        }
        if matches.count > 1 {
            let rest = matches.dropFirst()
            if rest.contains(where: { $0 != first }) {
                throw CodeSkillResolutionError.ambiguousEditTarget(matches.prefix(3).joined(separator: ", "))
            }
        }
        return first
    }

    static func command(
        category: CodeCommandCategory,
        workspaceRoot: URL,
        workspaceRelativePath: String? = nil,
        summary: String,
        arguments: [String] = [],
        touchesNetwork: Bool = false
    ) -> CommandSpec {
        CommandSpec(
            category: category,
            executable: "/usr/bin/env",
            arguments: arguments,
            workspaceRoot: workspaceRoot.path,
            workspaceRelativePath: workspaceRelativePath,
            summary: summary,
            touchesNetwork: touchesNetwork
        )
    }
}
