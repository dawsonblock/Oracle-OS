import Foundation

/// Routes a bound command to the appropriate action handler.
/// This is the ONLY place tools may be invoked from within Oracle-OS.
///
/// INVARIANT: ToolDispatcher is called only from VerifiedExecutor.
/// Nothing else may call dispatch() directly.
public struct ToolDispatcher: @unchecked Sendable {

    /// Optional automation host for UI commands (injected for testability).
    private let automationHost: AutomationHost?
    /// Optional workspace runner for code commands.
    private let workspaceRunner: WorkspaceRunner?
    /// Optional RuntimeContext for legacy code actions (bridge).
    private let context: RuntimeContext?

    public init(
        automationHost: AutomationHost? = nil,
        workspaceRunner: WorkspaceRunner? = nil,
        context: RuntimeContext? = nil
    ) {
        self.automationHost = automationHost
        self.workspaceRunner = workspaceRunner
        self.context = context
    }

    public func dispatch(
        _ command: any Command,
        capabilities: [String]
    ) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        let domain = CommandRouter.domain(for: command)
        switch domain {
        case .ui:
            return try await dispatchUI(command)
        case .code:
            return try await dispatchCode(command)
        case .system:
            return try await dispatchSystem(command)
        case .unknown:
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
    }

    // MARK: - Domain Dispatch

    private func dispatchUI(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        switch command.kind {
        case "clickElement":
            return try await dispatchClickElement(command)
        case "typeText":
            return try await dispatchTypeText(command)
        case "focusWindow":
            return try await dispatchFocusWindow(command)
        case "readElement":
            return try await dispatchReadElement(command)
        case "scrollElement":
            return try await dispatchScrollElement(command)
        default:
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
    }

    private func dispatchCode(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        switch command.kind {
        case "searchRepository":
            return try await dispatchSearchRepository(command)
        case "readFile":
            return try await dispatchReadFile(command)
        case "modifyFile":
            return try await dispatchModifyFile(command)
        case "runBuild":
            return try await dispatchRunBuild(command)
        case "runTests":
            return try await dispatchRunTests(command)
        default:
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
    }

    private func dispatchSystem(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        switch command.kind {
        case "launchApp":
            return try await dispatchLaunchApp(command)
        case "openURL":
            return try await dispatchOpenURL(command)
        default:
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
    }

    // MARK: - UI Command Dispatchers

    private func dispatchClickElement(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let host = automationHost else {
            throw ToolDispatcherError.capabilityNotAvailable("automationHost required for clickElement")
        }
        let targetID = (command as? ClickElementCommand)?.targetID ?? "unknown"
        let app = (command as? ClickElementCommand)?.applicationBundleID ?? ""
        let activated = await MainActor.run { host.applications.activateApplication(named: app) }
        let obs = ObservationPayload(kind: "click", content: "activated=\(activated) app=\(app) targetID=\(targetID)")
        return ([obs], [])
    }

    private func dispatchTypeText(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard automationHost != nil else {
            throw ToolDispatcherError.capabilityNotAvailable("automationHost required for typeText")
        }
        let text = (command as? TypeTextCommand)?.text ?? ""
        return ([ObservationPayload(kind: "type", content: "typed \(text.count) chars")], [])
    }

    private func dispatchFocusWindow(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let host = automationHost else {
            throw ToolDispatcherError.capabilityNotAvailable("automationHost required for focusWindow")
        }
        let app = (command as? FocusWindowCommand)?.applicationBundleID ?? ""
        let activated = await MainActor.run { host.applications.activateApplication(named: app) }
        return ([ObservationPayload(kind: "focus", content: "focused=\(activated) app=\(app)")], [])
    }

    private func dispatchReadElement(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard automationHost != nil else {
            throw ToolDispatcherError.capabilityNotAvailable("automationHost required for readElement")
        }
        let targetID = (command as? ReadElementCommand)?.targetID ?? "unknown"
        return ([ObservationPayload(kind: "read", content: "read element \(targetID)")], [])
    }

    private func dispatchScrollElement(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard automationHost != nil else {
            throw ToolDispatcherError.capabilityNotAvailable("automationHost required for scrollElement")
        }
        return ([ObservationPayload(kind: "scroll", content: "scroll dispatched")], [])
    }

    // MARK: - Code Command Dispatchers

    private func dispatchSearchRepository(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let ctx = context else {
            throw ToolDispatcherError.capabilityNotAvailable("RuntimeContext required for searchRepository")
        }
        let query = (command as? SearchRepositoryCommand)?.query ?? ""
        let root = await MainActor.run { ctx.config.traceDirectory.deletingLastPathComponent() }
        let snapshot = await MainActor.run { ctx.repositoryIndexer.indexIfNeeded(workspaceRoot: root) }
        let matches = CodeSearch().search(query: query, in: snapshot)
        let content = matches.prefix(10).map { "\($0.path) (\(String(format: "%.2f", $0.score)))" }.joined(separator: "\n")
        return ([ObservationPayload(kind: "searchResult", content: content.isEmpty ? "no matches" : content)], [])
    }

    private func dispatchReadFile(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        let path = (command as? ReadFileCommand)?.filePath ?? ""
        guard !path.isEmpty else { throw ToolDispatcherError.missingParameter("filePath") }
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            throw ToolDispatcherError.fileNotFound(path)
        }
        let obs = ObservationPayload(kind: "fileContent", content: text)
        let artifact = ArtifactPayload(kind: "file", identifier: path, data: data)
        return ([obs], [artifact])
    }

    private func dispatchModifyFile(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let cmd = command as? ModifyFileCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let path = cmd.filePath
        guard !path.isEmpty else { throw ToolDispatcherError.missingParameter("filePath") }
        let existing = FileManager.default.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let newContent = cmd.patch
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)
        let obs = ObservationPayload(kind: "fileModified",
            content: "modified \(path): \(existing.count)→\(newContent.count) chars")
        return ([obs], [ArtifactPayload(kind: "patch", identifier: path)])
    }

    private func dispatchRunBuild(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let ctx = context else {
            throw ToolDispatcherError.capabilityNotAvailable("RuntimeContext required for runBuild")
        }
        let workspacePath = (command as? RunBuildCommand)?.workspacePath
        let fallback = await MainActor.run { ctx.config.traceDirectory.deletingLastPathComponent().path }
        let root = workspacePath ?? fallback
        let spec = CommandSpec(
            category: .build,
            executable: "/usr/bin/env",
            arguments: ["swift", "build"],
            workspaceRoot: root,
            summary: "swift build"
        )
        let result = try await MainActor.run { try ctx.workspaceRunner.execute(spec: spec) }
        let obs = ObservationPayload(kind: "buildResult",
            content: "\(result.succeeded ? "PASS" : "FAIL") exit=\(result.exitCode) \(result.stderr.prefix(200))")
        return ([obs], [])
    }

    private func dispatchRunTests(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let ctx = context else {
            throw ToolDispatcherError.capabilityNotAvailable("RuntimeContext required for runTests")
        }
        let filter = (command as? RunTestsCommand)?.filter
        var args = ["swift", "test"]
        if let f = filter { args += ["--filter", f] }
        let root = await MainActor.run { ctx.config.traceDirectory.deletingLastPathComponent().path }
        let spec = CommandSpec(
            category: .test,
            executable: "/usr/bin/env",
            arguments: args,
            workspaceRoot: root,
            summary: "swift test\(filter.map { " --filter \($0)" } ?? "")"
        )
        let result = try await MainActor.run { try ctx.workspaceRunner.execute(spec: spec) }
        let obs = ObservationPayload(kind: "testResult",
            content: "\(result.succeeded ? "PASS" : "FAIL") exit=\(result.exitCode) \(result.stdout.prefix(200))")
        return ([obs], [])
    }

    // MARK: - System Command Dispatchers

    private func dispatchLaunchApp(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let host = automationHost else {
            throw ToolDispatcherError.capabilityNotAvailable("automationHost required for launchApp")
        }
        let bundleID = (command as? LaunchAppCommand)?.bundleID ?? ""
        let activated = await MainActor.run { host.applications.activateApplication(named: bundleID) }
        return ([ObservationPayload(kind: "launch", content: "activated=\(activated) bundleID=\(bundleID)")], [])
    }

    private func dispatchOpenURL(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        let urlString = (command as? OpenURLCommand)?.url.absoluteString ?? ""
        guard !urlString.isEmpty else {
            throw ToolDispatcherError.missingParameter("url")
        }
        return ([ObservationPayload(kind: "openURL", content: "url=\(urlString)")], [])
    }
}

// MARK: - Errors

public enum ToolDispatcherError: Error, CustomStringConvertible {
    case unsupportedCommandKind(String)
    case notImplemented(String)
    case capabilityNotAvailable(String)
    case missingParameter(String)
    case fileNotFound(String)

    public var description: String {
        switch self {
        case .unsupportedCommandKind(let kind): return "Unsupported command kind: \(kind)"
        case .notImplemented(let feature): return "Not implemented: \(feature)"
        case .capabilityNotAvailable(let cap): return "Capability not available: \(cap)"
        case .missingParameter(let param): return "Missing required parameter: \(param)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }
}
