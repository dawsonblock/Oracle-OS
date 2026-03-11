public struct ActionResult: Sendable, Codable {
    public let success: Bool
    public let verified: Bool
    public let message: String?
    public let method: String?
    public let verificationStatus: VerificationStatus?
    public let failureClass: String?
    public let elapsedMs: Double

    public init(
        success: Bool,
        verified: Bool? = nil,
        message: String? = nil,
        method: String? = nil,
        verificationStatus: VerificationStatus? = nil,
        failureClass: String? = nil,
        elapsedMs: Double = 0
    ) {
        self.success = success
        self.verified = verified ?? success
        self.message = message
        self.method = method
        self.verificationStatus = verificationStatus
        self.failureClass = failureClass
        self.elapsedMs = elapsedMs
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "success": success,
            "verified": verified,
            "elapsed_ms": elapsedMs,
        ]

        if let message {
            result["message"] = message
        }
        if let method {
            result["method"] = method
        }
        if let verificationStatus {
            result["verification_status"] = verificationStatus.rawValue
        }
        if let failureClass {
            result["failure_class"] = failureClass
        }

        return result
    }
}
