import Foundation

public struct TraceEvent: Codable, Sendable {
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

    public let postcondition: String?
    public let verified: Bool
    public let success: Bool
    public let failureClass: String?
    public let recoveryStrategy: String?

    public let elapsedMs: Double
    public let screenshotPath: String?
    public let notes: String?

    public init(
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
        postcondition: String? = nil,
        verified: Bool,
        success: Bool,
        failureClass: String? = nil,
        recoveryStrategy: String? = nil,
        elapsedMs: Double,
        screenshotPath: String? = nil,
        notes: String? = nil
    ) {
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
        self.postcondition = postcondition
        self.verified = verified
        self.success = success
        self.failureClass = failureClass
        self.recoveryStrategy = recoveryStrategy
        self.elapsedMs = elapsedMs
        self.screenshotPath = screenshotPath
        self.notes = notes
    }

    public init(action: String, success: Bool, message: String? = nil) {
        self.init(
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
            postcondition: nil,
            verified: success,
            success: success,
            failureClass: success ? nil : "compat_failure",
            recoveryStrategy: nil,
            elapsedMs: 0,
            screenshotPath: nil,
            notes: message
        )
    }
}
