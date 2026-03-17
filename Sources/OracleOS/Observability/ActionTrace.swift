import Foundation
public struct ActionTrace: Sendable, Codable {
    public let commandID: CommandID; public let intentID: UUID; public let startTime: Date; public let endTime: Date?
    public let domain: String; public let outcome: String?
    public init(commandID: CommandID, intentID: UUID, startTime: Date, endTime: Date? = nil, domain: String, outcome: String? = nil) {
        self.commandID = commandID; self.intentID = intentID; self.startTime = startTime
        self.endTime = endTime; self.domain = domain; self.outcome = outcome }
}
