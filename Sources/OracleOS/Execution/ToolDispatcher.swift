import Foundation

/// Routes a bound command to the appropriate action handler.
/// This is the ONLY place actions may be triggered.
public struct ToolDispatcher {
    public init() {}
    
    public func dispatch(_ command: any Command, capabilities: [String]) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        // Dispatch based on command kind - this is the core routing logic
        switch command.kind {
        case "clickElement":
            return try await dispatchClickElement(command)
        case "typeText":
            return try await dispatchTypeText(command)
        case "focusWindow":
            return try await dispatchFocusWindow(command)
        case "readElement":
            return try await dispatchReadElement(command)
        case "searchRepository", "modifyFile", "runBuild", "runTests", "readFile":
            return try await dispatchCodeCommand(command)
        case "launchApp", "openURL":
            return try await dispatchSystemCommand(command)
        default:
            throw ToolDispatcherError.unsupportedCommandKind(command.kind)
        }
    }
    
    // MARK: - UI Command Dispatchers
    
    private func dispatchClickElement(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        // TODO: Implement actual click action via platform automation
        throw ToolDispatcherError.notImplemented("clickElement")
    }
    
    private func dispatchTypeText(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        throw ToolDispatcherError.notImplemented("typeText")
    }
    
    private func dispatchFocusWindow(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        throw ToolDispatcherError.notImplemented("focusWindow")
    }
    
    private func dispatchReadElement(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        throw ToolDispatcherError.notImplemented("readElement")
    }
    
    // MARK: - Code Command Dispatchers
    
    private func dispatchCodeCommand(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        throw ToolDispatcherError.notImplemented("code command: \(command.kind)")
    }
    
    // MARK: - System Command Dispatchers
    
    private func dispatchSystemCommand(_ command: any Command) async throws -> (observations: [ObservationPayload], artifacts: [ArtifactPayload]) {
        throw ToolDispatcherError.notImplemented("system command: \(command.kind)")
    }
}

/// Errors thrown by ToolDispatcher
public enum ToolDispatcherError: Error, CustomStringConvertible {
    case unsupportedCommandKind(String)
    case notImplemented(String)
    case capabilityNotAvailable(String)
    
    public var description: String {
        switch self {
        case .unsupportedCommandKind(let kind):
            return "Unsupported command kind: \(kind)"
        case .notImplemented(let feature):
            return "Tool dispatcher not implemented for: \(feature)"
        case .capabilityNotAvailable(let capability):
            return "Required capability not available: \(capability)"
        }
    }
}
