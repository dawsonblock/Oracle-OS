import Foundation

// MARK: - Runtime Lifecycle Events
// These events are emitted at every stage of the runtime pipeline.
// Every success AND failure path must produce at least one event.

public struct IntentReceived: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let intentDomain: String
    public let objective: String
    public var eventType: String { "IntentReceived" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, intentDomain: String, objective: String) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.intentDomain = intentDomain; self.objective = objective
    }
}

public struct CommandPlanned: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let commandKind: String
    public let commandType: String
    public let planningStrategy: String
    public var eventType: String { "CommandPlanned" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, commandKind: String, commandType: String, planningStrategy: String) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.commandKind = commandKind; self.commandType = commandType
        self.planningStrategy = planningStrategy
    }
}

public struct CommandStarted: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let commandKind: String
    public var eventType: String { "CommandStarted" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, commandKind: String) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.commandKind = commandKind
    }
}

public struct CommandSucceeded: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let commandKind: String
    public let observationCount: Int
    public var eventType: String { "CommandSucceeded" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, commandKind: String, observationCount: Int = 0) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.commandKind = commandKind; self.observationCount = observationCount
    }
}

public struct CommandFailed: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let commandKind: String
    public let reason: String
    public var eventType: String { "CommandFailed" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, commandKind: String, reason: String) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.commandKind = commandKind; self.reason = reason
    }
}

public struct PolicyRejected: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let commandKind: String
    public let reason: String
    public var eventType: String { "PolicyRejected" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, commandKind: String, reason: String) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.commandKind = commandKind; self.reason = reason
    }
}

public struct StateCommitted: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let eventCount: Int
    public var eventType: String { "StateCommitted" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, eventCount: Int) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.eventCount = eventCount
    }
}

public struct EvaluationRecorded: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let criticOutcome: String
    public let needsRecovery: Bool
    public var eventType: String { "EvaluationRecorded" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, criticOutcome: String, needsRecovery: Bool) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.criticOutcome = criticOutcome; self.needsRecovery = needsRecovery
    }
}

public struct RecoveryTriggered: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let reason: String
    public let strategy: String
    public var eventType: String { "RecoveryTriggered" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, reason: String, strategy: String) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.reason = reason; self.strategy = strategy
    }
}

public struct RecoveryCompleted: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    public let success: Bool
    public let attempts: Int
    public var eventType: String { "RecoveryCompleted" }

    public init(aggregateId: String, correlationId: UUID, causationId: UUID? = nil, success: Bool, attempts: Int) {
        self.aggregateId = aggregateId; self.timestamp = Date(); self.correlationId = correlationId
        self.causationId = causationId; self.success = success; self.attempts = attempts
    }
}
