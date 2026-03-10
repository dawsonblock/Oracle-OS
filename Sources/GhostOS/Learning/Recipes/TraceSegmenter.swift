import Foundation

public struct TraceSegmenter {

    public static func segment(
        events: [TraceEvent]
    ) -> [TraceEvent] {

        // simple version: keep successful actions
        return events.filter { $0.result.success }
    }
}
