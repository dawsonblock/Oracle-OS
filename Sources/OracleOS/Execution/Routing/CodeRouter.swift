import Foundation

public struct CodeRouter: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner?
    private let repositoryIndexer: RepositoryIndexer

    init(
        workspaceRunner: WorkspaceRunner?,
        repositoryIndexer: RepositoryIndexer
    ) {
        self.workspaceRunner = workspaceRunner
        self.repositoryIndexer = repositoryIndexer
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> ExecutionOutcome {
        switch command.payload {
        case .shell(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

            let result = try workspaceRunner.execute(spec: spec)
            let observations = [
                ObservationPayload(
                    kind: "code.shell",
                    content: "\(result.summary)\nstdout:\n\(result.stdout)\nstderr:\n\(result.stderr)"
                ),
            ]
            if result.succeeded {
                return CommandRouter.successOutcome(
                    command: command,
                    observations: observations,
                    artifacts: [],
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

            return CommandRouter.failureOutcome(
                command: command,
                reason: result.stderr.isEmpty ? result.stdout : result.stderr,
                policyDecision: policyDecision,
                router: "code"
            )

        case .code(let action):
            return try executeCodeAction(
                action,
                command: command,
                policyDecision: policyDecision
            )

        case .ui:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid code payload",
                policyDecision: policyDecision,
                router: "code"
            )
        }
    }

    private func executeCodeAction(
        _ action: CodeAction,
        command: Command,
        policyDecision: PolicyDecision
    ) throws -> ExecutionOutcome {
        switch action.name {
        case "searchRepository":
            let workspaceRoot = action.workspacePath ?? FileManager.default.currentDirectoryPath
            let snapshot = repositoryIndexer.indexIfNeeded(
                workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
            )
            let matches = CodeSearch().search(query: action.query ?? "", in: snapshot)
            let content = matches
                .prefix(10)
                .map { "\($0.path) (\(String(format: "%.2f", $0.score)))" }
                .joined(separator: "\n")
            return CommandRouter.successOutcome(
                command: command,
                observations: [
                    ObservationPayload(
                        kind: "searchResult",
                        content: content.isEmpty ? "no matches" : content
                    ),
                ],
                artifacts: [],
                policyDecision: policyDecision,
                router: "code"
            )

        case "readFile":
            guard let resolvedPath = try resolvePath(filePath: action.filePath, workspacePath: action.workspacePath),
                  let data = FileManager.default.contents(atPath: resolvedPath.path),
                  let text = String(data: data, encoding: .utf8)
            else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Unable to read \(action.filePath ?? "file")",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }
            return CommandRouter.successOutcome(
                command: command,
                observations: [ObservationPayload(kind: "fileContent", content: text)],
                artifacts: [ArtifactPayload(kind: "file", identifier: resolvedPath.path, data: data)],
                policyDecision: policyDecision,
                router: "code"
            )

        case "modifyFile":
            guard let resolvedPath = try resolvePath(filePath: action.filePath, workspacePath: action.workspacePath) else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Unable to resolve \(action.filePath ?? "file")",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }
            let existing = FileManager.default.contents(atPath: resolvedPath.path)
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let newContent = action.patch ?? existing
            try newContent.write(to: resolvedPath, atomically: true, encoding: .utf8)
            return CommandRouter.successOutcome(
                command: command,
                observations: [
                    ObservationPayload(
                        kind: "fileModified",
                        content: "modified \(resolvedPath.path): \(existing.count)->\(newContent.count) chars"
                    ),
                ],
                artifacts: [ArtifactPayload(kind: "patch", identifier: resolvedPath.path)],
                policyDecision: policyDecision,
                router: "code"
            )

        default:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Unsupported code action: \(action.name)",
                policyDecision: policyDecision,
                router: "code"
            )
        }
    }

    private func resolvePath(filePath: String?, workspacePath: String?) throws -> URL? {
        guard let filePath, !filePath.isEmpty else { return nil }
        guard let workspacePath, !filePath.hasPrefix("/") else {
            return URL(fileURLWithPath: filePath)
        }

        let scope = try WorkspaceScope(rootURL: URL(fileURLWithPath: workspacePath, isDirectory: true))
        return try scope.resolve(relativePath: filePath)
    }
}
