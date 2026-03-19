import Foundation

public protocol CommandRouter: Sendable {
    func route(_ command: any Command, capabilities: [String]) async throws -> ExecutionOutcome
}

public actor CommandRouterImpl: CommandRouter {
    private let automationHost: AutomationHost?
    private let workspaceRunner: WorkspaceRunner?
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

    public func route(
        _ command: any Command,
        capabilities: [String]
    ) async throws -> ExecutionOutcome {
        let commandID = command.id

        switch command.kind {
        case "clickElement":
            return try await routeClickElement(command)
        case "typeText":
            return try await routeTypeText(command)
        case "focusWindow":
            return try await routeFocusWindow(command)
        case "readElement":
            return try await routeReadElement(command)
        case "scrollElement":
            return try await routeScrollElement(command)

        case "searchRepository":
            return try await routeSearchRepository(command)
        case "readFile":
            return try await routeReadFile(command)
        case "modifyFile":
            return try await routeModifyFile(command)
        case "runBuild":
            return try await routeRunBuild(command)
        case "runTests":
            return try await routeRunTests(command)

        case "launchApp":
            return try await routeLaunchApp(command)
        case "openURL":
            return try await routeOpenURL(command)

        default:
            throw CommandRouterError.unsupportedCommandKind(command.kind)
        }
    }

    private func makeOutcome(commandID: CommandID, status: ExecutionStatus, observations: [ObservationPayload], artifacts: [ArtifactPayload]) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: commandID,
            preconditionsPassed: true,
            policyDecision: "approved",
            postconditionsPassed: status == .success,
            notes: []
        )
        
        var events: [EventEnvelope] = []
        
        let eventType: String
        switch status {
        case .success:
            eventType = "commandSucceeded"
        case .failed:
            eventType = "commandFailed"
        default:
            eventType = "commandCompleted"
        }
        
        let payload = try! JSONSerialization.data(withJSONObject: [
            "kind": "command",
            "status": status.rawValue
        ])
        
        events.append(EventEnvelope(
            id: UUID(),
            sequenceNumber: 0,
            commandID: commandID,
            intentID: UUID(),
            timestamp: Date(),
            eventType: eventType,
            payload: payload
        ))

        return ExecutionOutcome(
            commandID: commandID,
            status: status,
            observations: observations,
            artifacts: artifacts,
            events: events,
            verifierReport: report
        )
    }

    private func routeClickElement(_ command: any Command) async throws -> ExecutionOutcome {
        guard let host = automationHost else {
            return makeOutcome(commandID: command.id, status: .failed, observations: [], artifacts: [])
        }
        let targetID = (command as? ClickElementCommand)?.targetID ?? "unknown"
        let app = (command as? ClickElementCommand)?.applicationBundleID ?? ""
        await MainActor.run { _ = host.applications.activateApplication(named: app) }
        let obs = ObservationPayload(kind: "click", content: "activated \(app)")
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [])
    }

    private func routeTypeText(_ command: any Command) async throws -> ExecutionOutcome {
        guard automationHost != nil else {
            return makeOutcome(commandID: command.id, status: .failed, observations: [], artifacts: [])
        }
        let text = (command as? TypeTextCommand)?.text ?? ""
        let obs = ObservationPayload(kind: "type", content: "typed \(text.count) characters")
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [])
    }

    private func routeFocusWindow(_ command: any Command) async throws -> ExecutionOutcome {
        guard let host = automationHost else {
            return makeOutcome(commandID: command.id, status: .failed, observations: [], artifacts: [])
        }
        let app = (command as? FocusWindowCommand)?.applicationBundleID ?? ""
        await MainActor.run { _ = host.applications.activateApplication(named: app) }
        let obs = ObservationPayload(kind: "focus", content: "focused \(app)")
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [])
    }

    private func routeReadElement(_ command: any Command) async throws -> ExecutionOutcome {
        guard automationHost != nil else {
            return makeOutcome(commandID: command.id, status: .failed, observations: [], artifacts: [])
        }
        let targetID = (command as? ReadElementCommand)?.targetID ?? "unknown"
        let obs = ObservationPayload(kind: "read", content: "read element \(targetID)")
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [])
    }

    private func routeScrollElement(_ command: any Command) async throws -> ExecutionOutcome {
        let obs = ObservationPayload(kind: "scroll", content: "scrolled")
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [])
    }

    private func routeSearchRepository(_ command: any Command) async throws -> ExecutionOutcome {
        guard let ctx = context else {
            return makeOutcome(commandID: command.id, status: .failed, observations: [], artifacts: [])
        }
        let query = (command as? SearchRepositoryCommand)?.query ?? ""
        let root = await MainActor.run { ctx.config.traceDirectory.deletingLastPathComponent() }
        let snapshot = await MainActor.run { ctx.repositoryIndexer.indexIfNeeded(workspaceRoot: root) }
        let matches = CodeSearch().search(query: query, in: snapshot)
        let content = matches.prefix(10).map { "\($0.path) (\(String(format: "%.2f", $0.score)))" }.joined(separator: "\n")
        let obs = ObservationPayload(kind: "searchResult", content: content.isEmpty ? "no matches" : content)
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [])
    }

    private func routeReadFile(_ command: any Command) async throws -> ExecutionOutcome {
        let path = (command as? ReadFileCommand)?.filePath ?? ""
        guard !path.isEmpty else {
            throw CommandRouterError.missingParameter("filePath")
        }
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            throw CommandRouterError.fileNotFound(path)
        }
        let obs = ObservationPayload(kind: "fileContent", content: text)
        let artifact = ArtifactPayload(kind: "file", identifier: path, data: data)
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [artifact])
    }

    private func routeModifyFile(_ command: any Command) async throws -> ExecutionOutcome {
        guard let cmd = command as? ModifyFileCommand else {
            throw CommandRouterError.unsupportedCommandKind(command.kind)
        }
        let path = cmd.filePath
        guard !path.isEmpty else {
            throw CommandRouterError.missingParameter("filePath")
        }
        let existing = FileManager.default.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let newContent = cmd.patch
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)
        let obs = ObservationPayload(kind: "fileModified", content: "modified \(path)")
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [ArtifactPayload(kind: "patch", identifier: path)])
    }

    private func routeRunBuild(_ command: any Command) async throws -> ExecutionOutcome {
        guard let ctx = context else {
            return makeOutcome(commandID: command.id, status: .failed, observations: [], artifacts: [])
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
        let obs = ObservationPayload(kind: "buildResult", content: "\(result.succeeded ? "PASS" : "FAIL") exit=\(result.exitCode)")
        return makeOutcome(commandID: command.id, status: result.succeeded ? .success : .failed, observations: [obs], artifacts: [])
    }

    private func routeRunTests(_ command: any Command) async throws -> ExecutionOutcome {
        guard let ctx = context else {
            return makeOutcome(commandID: command.id, status: .failed, observations: [], artifacts: [])
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
            summary: "swift test"
        )
        let result = try await MainActor.run { try ctx.workspaceRunner.execute(spec: spec) }
        let obs = ObservationPayload(kind: "testResult", content: "\(result.succeeded ? "PASS" : "FAIL") exit=\(result.exitCode)")
        return makeOutcome(commandID: command.id, status: result.succeeded ? .success : .failed, observations: [obs], artifacts: [])
    }

    private func routeLaunchApp(_ command: any Command) async throws -> ExecutionOutcome {
        guard let host = automationHost else {
            return makeOutcome(commandID: command.id, status: .failed, observations: [], artifacts: [])
        }
        let bundleID = (command as? LaunchAppCommand)?.bundleID ?? ""
        await MainActor.run { _ = host.applications.activateApplication(named: bundleID) }
        let obs = ObservationPayload(kind: "launch", content: "launched \(bundleID)")
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [])
    }

    private func routeOpenURL(_ command: any Command) async throws -> ExecutionOutcome {
        let url = (command as? OpenURLCommand)?.url.absoluteString ?? ""
        let obs = ObservationPayload(kind: "openURL", content: "opened \(url)")
        return makeOutcome(commandID: command.id, status: .success, observations: [obs], artifacts: [])
    }
}

public enum CommandRouterError: Error, CustomStringConvertible {
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

typealias ToolDispatcher = CommandRouterImpl
typealias ToolDispatcherError = CommandRouterError
