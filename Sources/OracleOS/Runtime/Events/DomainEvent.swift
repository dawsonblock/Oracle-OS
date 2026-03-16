// DomainEvent.swift — Core event protocol for Oracle OS event-sourcing runtime
//
// This file defines the core protocol for all domain events in the system.
// Event sourcing provides durable history where correctness matters,
// allowing reconstruction of committed state from event log.
//
// Core principles:
// - Events are immutable facts about what happened
// - Events are append-only (never modified after creation)
// - State changes derive from applying events through reducers
// - Projections provide queryable views from event stream

import Foundation

/// Base protocol for all domain events in the system.
/// 
/// Domain events represent authoritative facts about state changes.
/// They are the single source of truth for runtime state.
public protocol DomainEvent: Sendable, Codable {
    /// Unique type identifier for the event (e.g., "ActionExecuted")
    var eventType: String { get }
    
    /// Aggregate ID this event belongs to (task ID, session ID, etc.)
    var aggregateId: String { get }
    
    /// Timestamp when the event occurred
    var timestamp: Date { get }
    
    /// Correlation ID links related events in a flow
    var correlationId: UUID { get }
    
    /// Causation ID links to the event that caused this event
    var causationId: UUID? { get }
}

// MARK: - Common Event Types

/// Events emitted during action execution lifecycle
public struct ActionAuthorized: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let intentId: String
    public let actionType: String
    public let target: String?
    public let policyDecision: String
    
    public var eventType: String { "ActionAuthorized" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        intentId: String,
        actionType: String,
        target: String?,
        policyDecision: String
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.intentId = intentId
        self.actionType = actionType
        self.target = target
        self.policyDecision = policyDecision
    }
}

public struct PreStateObserved: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let observationHash: String
    public let planningStateId: String
    
    public var eventType: String { "PreStateObserved" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        observationHash: String,
        planningStateId: String
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.observationHash = observationHash
        self.planningStateId = planningStateId
    }
}

public struct ActionExecuted: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let actionType: String
    public let target: String?
    public let method: String
    public let success: Bool
    public let latencyMs: Int
    public let error: String?
    
    public var eventType: String { "ActionExecuted" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        actionType: String,
        target: String?,
        method: String,
        success: Bool,
        latencyMs: Int,
        error: String? = nil
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.actionType = actionType
        self.target = target
        self.method = method
        self.success = success
        self.latencyMs = latencyMs
        self.error = error
    }
}

public struct PostStateObserved: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let observationHash: String
    public let planningStateId: String
    
    public var eventType: String { "PostStateObserved" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        observationHash: String,
        planningStateId: String
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.observationHash = observationHash
        self.planningStateId = planningStateId
    }
}

public struct PostconditionVerified: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let postconditions: [String]
    public let allPassed: Bool
    public let failedChecks: [String]
    
    public var eventType: String { "PostconditionVerified" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        postconditions: [String],
        allPassed: Bool,
        failedChecks: [String] = []
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.postconditions = postconditions
        self.allPassed = allPassed
        self.failedChecks = failedChecks
    }
}

public struct PostconditionFailed: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let failedConditions: [String]
    public let error: String
    
    public var eventType: String { "PostconditionFailed" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        failedConditions: [String],
        error: String
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.failedConditions = failedConditions
        self.error = error
    }
}

public struct StateDriftDetected: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let expectedState: String
    public let actualState: String
    public let driftDescription: String
    
    public var eventType: String { "StateDriftDetected" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        expectedState: String,
        actualState: String,
        driftDescription: String
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.expectedState = expectedState
        self.actualState = actualState
        self.driftDescription = driftDescription
    }
}

public struct ArtifactProduced: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let artifactType: String
    public let artifactPath: String
    public let sizeBytes: Int?
    
    public var eventType: String { "ArtifactProduced" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        artifactType: String,
        artifactPath: String,
        sizeBytes: Int? = nil
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.artifactType = artifactType
        self.artifactPath = artifactPath
        self.sizeBytes = sizeBytes
    }
}

public struct ExecutionFailed: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let failureType: String
    public let error: String
    public let recoveryRequired: Bool
    
    public var eventType: String { "ExecutionFailed" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        failureType: String,
        error: String,
        recoveryRequired: Bool = true
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.failureType = failureType
        self.error = error
        self.recoveryRequired = recoveryRequired
    }
}

public struct CommandTimedOut: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let commandType: String
    public let timeoutSeconds: Double
    
    public var eventType: String { "CommandTimedOut" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        commandType: String,
        timeoutSeconds: Double
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.commandType = commandType
        self.timeoutSeconds = timeoutSeconds
    }
}

// MARK: - Recovery Events

public struct RecoveryStarted: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let failureEventId: UUID
    public let recoveryStrategy: String
    
    public var eventType: String { "RecoveryStarted" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        failureEventId: UUID,
        recoveryStrategy: String
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.failureEventId = failureEventId
        self.recoveryStrategy = recoveryStrategy
    }
}

public struct RecoveryActionExecuted: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let action: String
    public let success: Bool
    public let error: String?
    
    public var eventType: String { "RecoveryActionExecuted" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        action: String,
        success: Bool,
        error: String? = nil
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.action = action
        self.success = success
        self.error = error
    }
}

public struct RecoverySucceeded: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let attempts: Int
    public let finalState: String
    
    public var eventType: String { "RecoverySucceeded" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        attempts: Int,
        finalState: String
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.attempts = attempts
        self.finalState = finalState
    }
}

public struct RecoveryEscalated: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let reason: String
    public let escalationLevel: Int
    
    public var eventType: String { "RecoveryEscalated" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        reason: String,
        escalationLevel: Int
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.reason = reason
        self.escalationLevel = escalationLevel
    }
}

// MARK: - Critic Events

public struct CriticApprovedStep: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let score: Double
    public let reasoning: String
    
    public var eventType: String { "CriticApprovedStep" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        score: Double,
        reasoning: String
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.score = score
        self.reasoning = reasoning
    }
}

public struct CriticRejectedStep: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let reason: String
    public let suggestion: String?
    
    public var eventType: String { "CriticRejectedStep" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        reason: String,
        suggestion: String? = nil
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.reason = reason
        self.suggestion = suggestion
    }
}

public struct ReplanRequested: DomainEvent, Sendable, Codable {
    public let aggregateId: String
    public let timestamp: Date
    public let correlationId: UUID
    public let causationId: UUID?
    
    public let reason: String
    public let previousPlanId: String?
    
    public var eventType: String { "ReplanRequested" }
    
    public init(
        aggregateId: String,
        correlationId: UUID,
        causationId: UUID? = nil,
        reason: String,
        previousPlanId: String? = nil
    ) {
        self.aggregateId = aggregateId
        self.timestamp = Date()
        self.correlationId = correlationId
        self.causationId = causationId
        self.reason = reason
        self.previousPlanId = previousPlanId
    }
}