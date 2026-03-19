// MARK: - Command
// Oracle-OS — Typed representation of an executable action.
// Commands are SCHEMA ONLY. They carry no execution logic.
// Planners produce Commands. VerifiedExecutor consumes Commands.
// This is the final executable contract between planning and execution.

import Foundation

// MARK: CommandID

public struct CommandID: Sendable, Codable, Hashable, CustomStringConvertible {
    public let value: UUID
    public init(_ value: UUID = UUID()) { self.value = value }
    public var description: String { value.uuidString }
}

// MARK: CommandType

/// Classification of the command domain.
public enum CommandType: String, Sendable, Codable {
    case system
    case ui
    case code
}

// MARK: CommandMetadata

public struct CommandMetadata: Sendable, Codable {
    public let intentID: UUID
    public let createdAt: Date
    public let source: String
    public let traceTags: [String]
    public let planningStrategy: String
    public let rationale: String
    public let confidence: Double

    public init(
        intentID: UUID,
        createdAt: Date = Date(),
        source: String = "planner",
        traceTags: [String] = [],
        planningStrategy: String = "unknown",
        rationale: String = "",
        confidence: Double = 1.0
    ) {
        self.intentID = intentID
        self.createdAt = createdAt
        self.source = source
        self.traceTags = traceTags
        self.planningStrategy = planningStrategy
        self.rationale = rationale
        self.confidence = confidence
    }

    /// Backward-compatible accessor for callers using `timestamp`.
    public var timestamp: Date { createdAt }
}

// MARK: Command Protocol

/// The canonical executable unit crossing from planning into execution.
/// INVARIANT: Commands must never be self-executing.
/// Only VerifiedExecutor.execute(_:state:) may act on a Command.
public protocol Command: Sendable {
    var id: CommandID { get }
    var kind: String { get }
    var commandType: CommandType { get }
    var metadata: CommandMetadata { get }
}
