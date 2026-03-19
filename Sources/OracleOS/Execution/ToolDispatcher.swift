import AppKit
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
        _ = capabilities

        switch command.kind {
        // MARK: UI Commands
        case "clickElement":
            return try await dispatchClickElement(command)
        case "typeText":
            return try await dispatchTypeText(command)
        case "pressKey":
            return try await dispatchPressKey(command)
        case "hotkey":
            return try await dispatchHotkey(command)
        case "focusWindow":
            return try await dispatchFocusWindow(command)
        case "readElement":
            return try await dispatchReadElement(command)
        case "scrollElement":
            return try await dispatchScroll(command)
        case "manageWindow":
            return try await dispatchManageWindow(command)

        // MARK: Code Commands
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

        // MARK: System Commands
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
        guard let click = command as? ClickElementCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let result = await MainActor.run {
            Actions.performClick(
                query: click.query,
                role: click.role,
                domId: click.domID,
                appName: click.applicationBundleID,
                x: click.x,
                y: click.y,
                button: click.button,
                count: click.count
            )
        }
        return try groundedOutcome(from: result, kind: "click")
    }

    private func dispatchTypeText(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let type = command as? TypeTextCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let result = await MainActor.run {
            Actions.performTypeText(
                text: type.text,
                into: type.targetID == "focused" ? nil : type.targetID,
                domId: type.domID,
                appName: type.applicationBundleID,
                clear: type.clear
            )
        }
        return try groundedOutcome(from: result, kind: "type")
    }

    private func dispatchPressKey(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let press = command as? PressKeyCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let result = await MainActor.run {
            Actions.performPressKey(
                key: press.key,
                modifiers: press.modifiers,
                appName: press.applicationBundleID
            )
        }
        return try groundedOutcome(from: result, kind: "press")
    }

    private func dispatchHotkey(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let hotkey = command as? HotkeyCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let result = await MainActor.run {
            Actions.performHotkey(keys: hotkey.keys, appName: hotkey.applicationBundleID)
        }
        return try groundedOutcome(from: result, kind: "hotkey")
    }

    private func dispatchFocusWindow(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let focus = command as? FocusWindowCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let result = await MainActor.run {
            FocusManager.focus(appName: focus.applicationBundleID, windowTitle: focus.windowTitle)
        }
        return try groundedOutcome(from: result, kind: "focus")
    }

    private func dispatchReadElement(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let read = command as? ReadElementCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let result = await MainActor.run {
            AXScanner.readContent(appName: read.applicationBundleID, query: read.targetID, depth: nil)
        }
        return try groundedOutcome(from: result, kind: "read")
    }

    private func dispatchScroll(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let scroll = command as? ScrollCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let result = await MainActor.run {
            Actions.performScroll(
                direction: scroll.direction,
                amount: scroll.amount,
                appName: scroll.applicationBundleID,
                x: scroll.x,
                y: scroll.y
            )
        }
        return try groundedOutcome(from: result, kind: "scroll")
    }

    private func dispatchManageWindow(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let window = command as? ManageWindowCommand else {
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
        let result = await MainActor.run {
            Actions.performWindowAction(
                action: window.action,
                appName: window.applicationBundleID,
                windowTitle: window.windowTitle,
                x: window.x,
                y: window.y,
                width: window.width,
                height: window.height
            )
        }
        return try groundedOutcome(from: result, kind: "window")
    }

    // MARK: - Code Command Dispatchers

    private func dispatchSearchRepository(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let ctx = context else {
            throw ToolDispatcherError.capabilityNotAvailable("repository search requires runtime context")
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
            throw ToolDispatcherError.capabilityNotAvailable("build requires runtime context")
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
            throw ToolDispatcherError.capabilityNotAvailable("tests require runtime context")
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
        let bundleID = (command as? LaunchAppCommand)?.bundleID ?? ""
        if let host = automationHost {
            await MainActor.run { _ = host.applications.activateApplication(named: bundleID) }
            return ([ObservationPayload(kind: "launch", content: "launched \(bundleID)")], [])
        }

        let result = await MainActor.run {
            FocusManager.focus(appName: bundleID)
        }
        return try groundedOutcome(from: result, kind: "launch")
    }

    private func dispatchOpenURL(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard let url = (command as? OpenURLCommand)?.url else {
            throw ToolDispatcherError.missingParameter("url")
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else {
            throw ToolDispatcherError.executionFailed("Unable to open URL \(url.absoluteString)")
        }
        return ([ObservationPayload(kind: "openURL", content: "opened \(url.absoluteString)")], [])
    }

    private func groundedOutcome(
        from result: ToolResult,
        kind: String
    ) throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        guard result.success else {
            throw ToolDispatcherError.executionFailed(result.error ?? "\(kind) failed")
        }

        let summary: String
        if let method = result.data?["method"] as? String {
            summary = "\(kind): \(method)"
        } else if let action = result.data?["action"] as? String {
            summary = "\(kind): \(action)"
        } else {
            summary = "\(kind) succeeded"
        }

        var artifacts: [ArtifactPayload] = []
        if let data = try? JSONSerialization.data(withJSONObject: result.toDict(), options: [.sortedKeys]) {
            artifacts.append(ArtifactPayload(kind: "toolResult", identifier: kind, data: data))
        }

        return ([ObservationPayload(kind: kind, content: summary)], artifacts)
    }
}

// MARK: - Errors

public enum ToolDispatcherError: Error, CustomStringConvertible {
    case unsupportedCommandKind(String)
    case notImplemented(String)
    case capabilityNotAvailable(String)
    case missingParameter(String)
    case fileNotFound(String)
    case executionFailed(String)

    public var description: String {
        switch self {
        case .unsupportedCommandKind(let kind): return "Unsupported command kind: \(kind)"
        case .notImplemented(let feature): return "Not implemented: \(feature)"
        case .capabilityNotAvailable(let cap): return "Capability not available: \(cap)"
        case .missingParameter(let param): return "Missing required parameter: \(param)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .executionFailed(let message): return "Execution failed: \(message)"
        }
    }
}
