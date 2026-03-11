import Foundation

public protocol AgentExecutionDriver {
    func execute(_ actionContract: ActionContract) -> ToolResult
}
