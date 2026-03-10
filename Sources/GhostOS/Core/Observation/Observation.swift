import Foundation

public struct Observation: Sendable, Codable {

    public let timestamp: Date

    public let app: String?
    public let windowTitle: String?
    public let url: String?
    public let focusedElementID: String?
    public let elements: [UnifiedElement]

    public init(
        app: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        focusedElementID: String? = nil,
        elements: [UnifiedElement] = []
    ) {
        self.timestamp = Date()
        self.app = app
        self.windowTitle = windowTitle
        self.url = url
        self.focusedElementID = focusedElementID
        self.elements = elements
    }

    public func stableHash() -> String {
        let content = elements.map { $0.id }.joined(separator: ",")
        return "\(app ?? "none"):\(content)".data(using: .utf8)?.base64EncodedString() ?? "hash-err"
    }
}
