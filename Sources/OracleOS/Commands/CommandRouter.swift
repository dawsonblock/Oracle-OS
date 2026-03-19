import Foundation

/// Routes a Command to the correct executor domain.
/// This is the single dispatch point between VerifiedExecutor and domain routers.
public enum CommandRouter {
    public enum Domain: String, Sendable { case ui, code, system, unknown }

    public static func domain(for command: any Command) -> Domain {
        switch command.commandType {
        case .ui: return .ui
        case .code: return .code
        case .system: return .system
        }
    }
}
