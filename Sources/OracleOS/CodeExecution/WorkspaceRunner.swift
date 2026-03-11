import Foundation

public enum WorkspaceRunnerError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedCommand(String)
    case scopeViolation(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedCommand(summary):
            "Unsupported command: \(summary)"
        case let .scopeViolation(message):
            message
        }
    }
}

public final class WorkspaceRunner: @unchecked Sendable {
    public init() {}

    public func execute(spec: CommandSpec) throws -> CommandResult {
        guard isAllowed(spec) else {
            throw WorkspaceRunnerError.unsupportedCommand(spec.summary)
        }

        let scope = try WorkspaceScope(rootURL: URL(fileURLWithPath: spec.workspaceRoot, isDirectory: true))
        _ = try scope.resolve(relativePath: spec.workspaceRelativePath)

        let start = Date()
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments
        process.currentDirectoryURL = scope.rootURL
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = sanitizedEnvironment()

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            succeeded: process.terminationStatus == 0,
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            elapsedMs: Date().timeIntervalSince(start) * 1000.0,
            workspaceRoot: spec.workspaceRoot,
            category: spec.category,
            summary: spec.summary
        )
    }

    private func isAllowed(_ spec: CommandSpec) -> Bool {
        switch spec.category {
        case .build, .test, .formatter, .linter, .gitStatus, .gitBranch, .gitCommit, .gitPush:
            return allowedGitCommand(spec) && allowedExecutable(spec.executable)
        case .indexRepository, .searchCode, .openFile, .editFile, .writeFile, .generatePatch, .parseBuildFailure, .parseTestFailure:
            return true
        }
    }

    private func allowedExecutable(_ executable: String) -> Bool {
        let allowedExecutables = [
            "/usr/bin/env",
            "/usr/bin/git",
        ]
        return allowedExecutables.contains(executable)
    }

    private func allowedGitCommand(_ spec: CommandSpec) -> Bool {
        guard spec.category.isGit else { return true }
        let joined = spec.arguments.joined(separator: " ").lowercased()

        if joined.contains("--force") || joined.contains(" push --force") {
            return false
        }
        if joined.contains("push --delete") {
            return false
        }
        return true
    }

    private func sanitizedEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let keys = ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "DEVELOPER_DIR"]
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            source[key].map { (key, $0) }
        })
    }
}
