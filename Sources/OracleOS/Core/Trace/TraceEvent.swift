import Foundation

public struct TraceEvent: Codable, Sendable {
    public let schemaVersion: Int
    public let sessionID: String
    public let taskID: String?
    public let stepID: Int
    public let timestamp: Date

    public let toolName: String?
    public let actionName: String
    public let actionTarget: String?
    public let actionText: String?

    public let selectedElementID: String?
    public let selectedElementLabel: String?
    public let candidateScore: Double?
    public let candidateReasons: [String]

    public let preObservationHash: String?
    public let postObservationHash: String?
    public let planningStateID: String?
    public let beliefSnapshotID: String?

    public let postcondition: String?
    public let postconditionClass: String?
    public let actionContractID: String?
    public let executionMode: String?
    public let verified: Bool
    public let success: Bool
    public let failureClass: String?
    public let recoveryStrategy: String?
    public let recoverySource: String?

    public let elapsedMs: Double
    public let screenshotPath: String?
    public let notes: String?

    public init(
        schemaVersion: Int = TraceSchemaVersion.current,
        sessionID: String,
        taskID: String?,
        stepID: Int,
        toolName: String?,
        actionName: String,
        actionTarget: String? = nil,
        actionText: String? = nil,
        selectedElementID: String? = nil,
        selectedElementLabel: String? = nil,
        candidateScore: Double? = nil,
        candidateReasons: [String] = [],
        preObservationHash: String? = nil,
        postObservationHash: String? = nil,
        planningStateID: String? = nil,
        beliefSnapshotID: String? = nil,
        postcondition: String? = nil,
        postconditionClass: String? = nil,
        actionContractID: String? = nil,
        executionMode: String? = nil,
        verified: Bool,
        success: Bool,
        failureClass: String? = nil,
        recoveryStrategy: String? = nil,
        recoverySource: String? = nil,
        elapsedMs: Double,
        screenshotPath: String? = nil,
        notes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.taskID = taskID
        self.stepID = stepID
        self.timestamp = Date()
        self.toolName = toolName
        self.actionName = actionName
        self.actionTarget = actionTarget
        self.actionText = actionText
        self.selectedElementID = selectedElementID
        self.selectedElementLabel = selectedElementLabel
        self.candidateScore = candidateScore
        self.candidateReasons = candidateReasons
        self.preObservationHash = preObservationHash
        self.postObservationHash = postObservationHash
        self.planningStateID = planningStateID
        self.beliefSnapshotID = beliefSnapshotID
        self.postcondition = postcondition
        self.postconditionClass = postconditionClass
        self.actionContractID = actionContractID
        self.executionMode = executionMode
        self.verified = verified
        self.success = success
        self.failureClass = failureClass
        self.recoveryStrategy = recoveryStrategy
        self.recoverySource = recoverySource
        self.elapsedMs = elapsedMs
        self.screenshotPath = screenshotPath
        self.notes = notes
    }

    public init(action: String, success: Bool, message: String? = nil) {
        self.init(
            schemaVersion: TraceSchemaVersion.current,
            sessionID: "compat",
            taskID: nil,
            stepID: 0,
            toolName: nil,
            actionName: action,
            actionTarget: nil,
            actionText: nil,
            selectedElementID: nil,
            selectedElementLabel: nil,
            candidateScore: nil,
            candidateReasons: [],
            preObservationHash: nil,
            postObservationHash: nil,
            planningStateID: nil,
            beliefSnapshotID: nil,
            postcondition: nil,
            postconditionClass: nil,
            actionContractID: nil,
            executionMode: "compat",
            verified: success,
            success: success,
            failureClass: success ? nil : "compat_failure",
            recoveryStrategy: nil,
            recoverySource: nil,
            elapsedMs: 0,
            screenshotPath: nil,
            notes: message
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sessionID
        case taskID
        case stepID
        case timestamp
        case toolName
        case actionName
        case actionTarget
        case actionText
        case selectedElementID
        case selectedElementLabel
        case candidateScore
        case candidateReasons
        case preObservationHash
        case postObservationHash
        case planningStateID
        case beliefSnapshotID
        case postcondition
        case postconditionClass
        case actionContractID
        case executionMode
        case verified
        case success
        case failureClass
        case recoveryStrategy
        case recoverySource
        case elapsedMs
        case screenshotPath
        case notes

        // Legacy keys
        case action
        case message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        let decodedActionName = try container.decodeIfPresent(String.self, forKey: .actionName)
        let legacyActionName = try container.decodeIfPresent(String.self, forKey: .action)
        let decodedNotes = try container.decodeIfPresent(String.self, forKey: .notes)
        let legacyMessage = try container.decodeIfPresent(String.self, forKey: .message)

        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? "legacy"
        self.taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
        self.stepID = try container.decodeIfPresent(Int.self, forKey: .stepID) ?? 0
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date(timeIntervalSince1970: 0)
        self.toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        self.actionName = decodedActionName ?? legacyActionName ?? "unknown"
        self.actionTarget = try container.decodeIfPresent(String.self, forKey: .actionTarget)
        self.actionText = try container.decodeIfPresent(String.self, forKey: .actionText)
        self.selectedElementID = try container.decodeIfPresent(String.self, forKey: .selectedElementID)
        self.selectedElementLabel = try container.decodeIfPresent(String.self, forKey: .selectedElementLabel)
        self.candidateScore = try container.decodeIfPresent(Double.self, forKey: .candidateScore)
        self.candidateReasons = try container.decodeIfPresent([String].self, forKey: .candidateReasons) ?? []
        self.preObservationHash = try container.decodeIfPresent(String.self, forKey: .preObservationHash)
        self.postObservationHash = try container.decodeIfPresent(String.self, forKey: .postObservationHash)
        self.planningStateID = try container.decodeIfPresent(String.self, forKey: .planningStateID)
        self.beliefSnapshotID = try container.decodeIfPresent(String.self, forKey: .beliefSnapshotID)
        self.postcondition = try container.decodeIfPresent(String.self, forKey: .postcondition)
        self.postconditionClass = try container.decodeIfPresent(String.self, forKey: .postconditionClass)
        self.actionContractID = try container.decodeIfPresent(String.self, forKey: .actionContractID)
        self.executionMode = try container.decodeIfPresent(String.self, forKey: .executionMode)
        self.verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? success
        self.success = success
        self.failureClass = try container.decodeIfPresent(String.self, forKey: .failureClass)
        self.recoveryStrategy = try container.decodeIfPresent(String.self, forKey: .recoveryStrategy)
        self.recoverySource = try container.decodeIfPresent(String.self, forKey: .recoverySource)
        self.elapsedMs = try container.decodeIfPresent(Double.self, forKey: .elapsedMs) ?? 0
        self.screenshotPath = try container.decodeIfPresent(String.self, forKey: .screenshotPath)
        self.notes = decodedNotes ?? legacyMessage
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(taskID, forKey: .taskID)
        try container.encode(stepID, forKey: .stepID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encode(actionName, forKey: .actionName)
        try container.encodeIfPresent(actionTarget, forKey: .actionTarget)
        try container.encodeIfPresent(actionText, forKey: .actionText)
        try container.encodeIfPresent(selectedElementID, forKey: .selectedElementID)
        try container.encodeIfPresent(selectedElementLabel, forKey: .selectedElementLabel)
        try container.encodeIfPresent(candidateScore, forKey: .candidateScore)
        try container.encode(candidateReasons, forKey: .candidateReasons)
        try container.encodeIfPresent(preObservationHash, forKey: .preObservationHash)
        try container.encodeIfPresent(postObservationHash, forKey: .postObservationHash)
        try container.encodeIfPresent(planningStateID, forKey: .planningStateID)
        try container.encodeIfPresent(beliefSnapshotID, forKey: .beliefSnapshotID)
        try container.encodeIfPresent(postcondition, forKey: .postcondition)
        try container.encodeIfPresent(postconditionClass, forKey: .postconditionClass)
        try container.encodeIfPresent(actionContractID, forKey: .actionContractID)
        try container.encodeIfPresent(executionMode, forKey: .executionMode)
        try container.encode(verified, forKey: .verified)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(failureClass, forKey: .failureClass)
        try container.encodeIfPresent(recoveryStrategy, forKey: .recoveryStrategy)
        try container.encodeIfPresent(recoverySource, forKey: .recoverySource)
        try container.encode(elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(screenshotPath, forKey: .screenshotPath)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}
