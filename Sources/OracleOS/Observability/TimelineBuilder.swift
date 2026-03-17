import Foundation
/// Builds a unified timeline from events for replay/debugging.
public struct TimelineBuilder {
    public init() {}
    public func build(from events: [EventEnvelope]) -> Timeline { Timeline(events: events) }
}
public struct Timeline: Sendable { public let events: [EventEnvelope] }
