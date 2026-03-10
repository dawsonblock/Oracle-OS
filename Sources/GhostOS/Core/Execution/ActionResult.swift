public struct ActionResult: Sendable, Codable {
    public let success: Bool
    public let message: String?
    public let method: String?
    public let verificationStatus: VerificationStatus?
    public let failureClass: String?

    public init(
        success: Bool,
        message: String? = nil,
        method: String? = nil,
        verificationStatus: VerificationStatus? = nil,
        failureClass: String? = nil
    ) {
        self.success = success
        self.message = message
        self.method = method
        self.verificationStatus = verificationStatus
        self.failureClass = failureClass
    }
}
