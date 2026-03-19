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
        _ command: Command,
        capabilities: [String]
    ) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        _ = capabilities
        switch command.payload {
        case .ui(let action):
            return try await dispatchUI(action)
        case .shell(let spec):
            return try await dispatchShell(spec)
        case .code(let action):
            return try await dispatchCode(action)
        }
    }

    // MARK: - UI dispatch

    private func dispatchUI(_ action: UIAction) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        let result = await MainActor.run { () -> ToolResult in
            switch action.name {
            case "click", "clickElement":
                return Actions.click(
                    query: action.query,
                    role: action.role,
                    domId: action.domID,
                    appName: action.app,
                    x: action.x,
                    y: action.y,
                    button: action.button,
                    count: action.count
                )
            case "type", "typeText":
                return Actions.typeText(
                    text: action.text ?? "",
                    into: action.query,
                    domId: action.domID,
                    appName: action.app,
                    clear: action.clear ?? false
                )
            case "focus", "focusWindow", "launchApp":
                return Actions.focusApp(appName: action.app ?? "unknown", windowTitle: action.windowTitle)
            case "press":
                let modifiers = action.modifiers ?? action.role?.split(separator: "+").map(String.init)
                return Actions.pressKey(key: action.query ?? "", modifiers: modifiers, appName: action.app)
            case "hotkey":
                let keys = action.modifiers
                    ?? action.query?.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
                    ?? []
                return Actions.hotkey(keys: keys, appName: action.app)
            case "scroll", "scrollElement":
                return Actions.scroll(
                    direction: action.query ?? "down",
                    amount: action.amount ?? action.count,
                    appName: action.app,
                    x: action.x,
                    y: action.y
                )
            case "openURL":
                guard let rawURL = action.query, let url = URL(string: rawURL) else {
                    return ToolResult(success: false, error: "Invalid URL: \(action.query ?? "nil")")
                }
                let opened = NSWorkspace.shared.open(url)
                return ToolResult(
                    success: opened,
                    data: opened ? ["url": rawURL] : nil,
                    error: opened ? nil : "Failed to open URL '\(rawURL)'"
                )
            case "window", "manageWindow":
                return Actions.manageWindow(
                    action: action.query ?? "list",
                    appName: action.app ?? "unknown",
                    windowTitle: action.windowTitle,
                    x: action.x,
                    y: action.y,
                    width: action.width,
                    height: action.height
                )
            case "read", "readElement":
                return AXScanner.readContent(appName: action.app, query: action.query, depth: nil)
            default:
                return ToolResult(success: false, error: "Unsupported UI action: \(action.name)")
            }
        }
        return toolResultToArtifacts(result, kind: "ui:\(action.name)")
    }

    // MARK: - Shell dispatch

    private func dispatchShell(_ spec: CommandSpec) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        let runner = workspaceRunner ?? context?.workspaceRunner
        guard let runner else {
            throw ToolDispatcherError.capabilityNotAvailable("workspaceRunner")
        }
        let result = try runner.execute(spec: spec)
        let summary = result.succeeded ? "PASS" : "FAIL"
        let obs = ObservationPayload(
            kind: "shell",
            content: "\(summary) exit=\(result.exitCode) \(result.summary)"
        )
        return ([obs], [])
    }

    // MARK: - Code dispatch

    private func dispatchCode(_ action: CodeAction) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        switch action.name {
        case "searchRepository":
            guard let ctx = context else {
                throw ToolDispatcherError.capabilityNotAvailable("repositoryIndexer")
            }
            let query = action.query ?? ""
            let root = await MainActor.run { ctx.config.traceDirectory.deletingLastPathComponent() }
            let snapshot = await MainActor.run { ctx.repositoryIndexer.indexIfNeeded(workspaceRoot: root) }
            let matches = CodeSearch().search(query: query, in: snapshot)
            let content = matches.prefix(10).map { "\($0.path) (\(String(format: "%.2f", $0.score)))" }.joined(separator: "\n")
            return ([ObservationPayload(kind: "searchResult", content: content.isEmpty ? "no matches" : content)], [])

        case "readFile":
            let path = action.filePath ?? ""
            guard !path.isEmpty else { throw ToolDispatcherError.missingParameter("filePath") }
            guard let data = FileManager.default.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8)
            else {
                throw ToolDispatcherError.fileNotFound(path)
            }
            return ([ObservationPayload(kind: "fileContent", content: text)], [ArtifactPayload(kind: "file", identifier: path, data: data)])

        case "modifyFile":
            let path = action.filePath ?? ""
            guard !path.isEmpty else { throw ToolDispatcherError.missingParameter("filePath") }
            let existing = FileManager.default.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let newContent = action.patch ?? existing
            try newContent.write(toFile: path, atomically: true, encoding: .utf8)
            return (
                [ObservationPayload(kind: "fileModified", content: "modified \(path): \(existing.count)→\(newContent.count) chars")],
                [ArtifactPayload(kind: "patch", identifier: path)]
            )

        default:
            throw ToolDispatcherError.unsupportedCommandKind(action.name)
        }
    }

    private func toolResultToArtifacts(
        _ result: ToolResult,
        kind: String
    ) -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        var content = result.success ? "success" : "failed"
        if let error = result.error, !error.isEmpty {
            content += ": \(error)"
        }
        return ([ObservationPayload(kind: kind, content: content)], [])
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
