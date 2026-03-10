import Foundation

public struct TraceEvent: Codable {

    public let timestamp: Date
    public let sessionID: String
    public let intent: ActionIntent
    public let result: ActionResult
    
    public let preObservationHash: String?
    public let postObservationHash: String?
    
    public let verification: VerificationSummary
    public let elapsedMs: Int
    public let failureClass: String?
    public let artifacts: TraceArtifactReferences?

    public init(
        sessionID: String,
        intent: ActionIntent,
        result: ActionResult,
        preObservationHash: String? = nil,
        postObservationHash: String? = nil,
        verification: VerificationSummary,
        elapsedMs: Int,
        failureClass: String? = nil,
        artifacts: TraceArtifactReferences? = nil
    ) {
        self.timestamp = Date()
        self.sessionID = sessionID
        self.intent = intent
        self.result = result
        self.preObservationHash = preObservationHash
        self.postObservationHash = postObservationHash
        self.verification = verification
        self.elapsedMs = elapsedMs
        self.failureClass = failureClass
        self.artifacts = artifacts
    }

    // Retain old init for compatibility if needed, though strictly we should just use the new one.
    public init(action: String, success: Bool, message: String? = nil) {
        self.timestamp = Date()
        self.sessionID = "compat"
        self.intent = ActionIntent(app: "unknown", action: action)
        self.result = ActionResult(success: success, message: message)
        self.verification = VerificationSummary(status: success ? .passed : .notAttempted, checks: [])
        self.elapsedMs = 0
        self.failureClass = nil
        self.artifacts = nil
        self.preObservationHash = nil
        self.postObservationHash = nil
    }
}

public struct TraceArtifactReferences: Codable {
    public let screenshotPath: String?
    public let preObservationPath: String?
    public let postObservationPath: String?
}
