import Foundation

public struct ExecutionOutcome: Sendable {
    public let commandID: CommandID
    public let status: ExecutionStatus
    public let observations: [ObservationPayload]
    public let artifacts: [ArtifactPayload]
    public let events: [EventEnvelope]
    public let verifierReport: VerifierReport

    public init(
        commandID: CommandID,
        status: ExecutionStatus,
        observations: [ObservationPayload] = [],
        artifacts: [ArtifactPayload] = [],
        events: [EventEnvelope],
        verifierReport: VerifierReport
    ) {
        self.commandID = commandID
        self.status = status
        self.observations = observations
        self.artifacts = artifacts
        self.events = events
        self.verifierReport = verifierReport
    }

    public static func failure(_ error: Error, commandID: CommandID) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: commandID,
            preconditionsPassed: true,
            policyDecision: "approved",
            postconditionsPassed: false,
            notes: [error.localizedDescription]
        )
        
        let payload = try! JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])
        
        let event = EventEnvelope(
            id: UUID(),
            sequenceNumber: 0,
            commandID: commandID,
            intentID: UUID(),
            timestamp: Date(),
            eventType: "commandFailed",
            payload: payload
        )
        
        return ExecutionOutcome(
            commandID: commandID,
            status: .failed,
            observations: [],
            artifacts: [],
            events: [event],
            verifierReport: report
        )
    }

    public static func success(commandID: CommandID, observations: [ObservationPayload] = [], artifacts: [ArtifactPayload] = []) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: commandID,
            preconditionsPassed: true,
            policyDecision: "approved",
            postconditionsPassed: true,
            notes: []
        )
        
        let payload = try! JSONSerialization.data(withJSONObject: ["status": "success"])
        
        let event = EventEnvelope(
            id: UUID(),
            sequenceNumber: 0,
            commandID: commandID,
            intentID: UUID(),
            timestamp: Date(),
            eventType: "commandSucceeded",
            payload: payload
        )
        
        return ExecutionOutcome(
            commandID: commandID,
            status: .success,
            observations: observations,
            artifacts: artifacts,
            events: [event],
            verifierReport: report
        )
    }
}

public enum ExecutionStatus: String, Sendable, Codable {
    case success, failed, partialSuccess, preconditionFailed, policyBlocked, postconditionFailed
}

public struct VerifierReport: Sendable, Codable {
    public let commandID: CommandID
    public let preconditionsPassed: Bool
    public let policyDecision: String
    public let postconditionsPassed: Bool
    public let notes: [String]
    public let timestamp: Date

    public init(commandID: CommandID, preconditionsPassed: Bool, policyDecision: String,
                postconditionsPassed: Bool, notes: [String] = [], timestamp: Date = Date()) {
        self.commandID = commandID
        self.preconditionsPassed = preconditionsPassed
        self.policyDecision = policyDecision
        self.postconditionsPassed = postconditionsPassed
        self.notes = notes
        self.timestamp = timestamp
    }
}

public struct ObservationPayload: Sendable, Codable {
    public let kind: String
    public let content: String
    public let timestamp: Date
    public init(kind: String, content: String, timestamp: Date = Date()) {
        self.kind = kind
        self.content = content
        self.timestamp = timestamp
    }
}

public struct ArtifactPayload: Sendable, Codable {
    public let kind: String
    public let identifier: String
    public let data: Data?
    public init(kind: String, identifier: String, data: Data? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.data = data
    }
}

public struct EvaluationResult: Sendable {
    public let commandID: CommandID
    public let criticOutcome: CriticOutcome
    public let needsRecovery: Bool
    public let notes: [String]

    public init(commandID: CommandID, criticOutcome: CriticOutcome, needsRecovery: Bool, notes: [String] = []) {
        self.commandID = commandID
        self.criticOutcome = criticOutcome
        self.needsRecovery = needsRecovery
        self.notes = notes
    }
}
