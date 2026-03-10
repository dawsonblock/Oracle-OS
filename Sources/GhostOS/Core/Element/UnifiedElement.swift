import Foundation
import CoreGraphics

public struct UnifiedElement: Sendable, Codable, Identifiable {

    public let id: String
    public let source: ElementSource

    public let role: String?
    public let label: String?
    public let value: String?

    public let frame: CGRect?

    public let enabled: Bool
    public let visible: Bool
    public let focused: Bool

    public let confidence: Double

    public init(
        id: String,
        source: ElementSource,
        role: String? = nil,
        label: String? = nil,
        value: String? = nil,
        frame: CGRect? = nil,
        enabled: Bool = true,
        visible: Bool = true,
        focused: Bool = false,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.source = source
        self.role = role
        self.label = label
        self.value = value
        self.frame = frame
        self.enabled = enabled
        self.visible = visible
        self.focused = focused
        self.confidence = confidence
    }
}
