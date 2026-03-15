import Foundation

public struct ExpectationModel: Sendable {
    public let expectedApp: String?
    public let expectedElements: [String]
    
    public init(expectedApp: String? = nil, expectedElements: [String] = []) {
        self.expectedApp = expectedApp
        self.expectedElements = expectedElements
    }
}
