import Foundation

public struct CodeMemoryStore: Sendable {
    public var errorPatterns: [String: ErrorPattern]
    public var fixPatterns: [String: FixPattern]
    public var commandSuccesses: [String: Int]
    public var commandFailures: [String: Int]

    public init(
        errorPatterns: [String: ErrorPattern] = [:],
        fixPatterns: [String: FixPattern] = [:],
        commandSuccesses: [String: Int] = [:],
        commandFailures: [String: Int] = [:]
    ) {
        self.errorPatterns = errorPatterns
        self.fixPatterns = fixPatterns
        self.commandSuccesses = commandSuccesses
        self.commandFailures = commandFailures
    }
}
