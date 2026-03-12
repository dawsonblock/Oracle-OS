import Foundation

public struct CompressedTracePattern: Sendable, Equatable {
    public let stateFingerprint: String
    public let actionName: String
    public let resultSuccess: Bool
    public let occurrences: Int
    public let averageElapsedMs: Double

    public init(
        stateFingerprint: String,
        actionName: String,
        resultSuccess: Bool,
        occurrences: Int,
        averageElapsedMs: Double
    ) {
        self.stateFingerprint = stateFingerprint
        self.actionName = actionName
        self.resultSuccess = resultSuccess
        self.occurrences = occurrences
        self.averageElapsedMs = averageElapsedMs
    }
}

public struct TraceCompressor: Sendable {

    public init() {}

    public func compress(events: [TraceEvent]) -> [CompressedTracePattern] {
        var grouped: [String: [TraceEvent]] = [:]
        for event in events {
            let key = patternKey(for: event)
            grouped[key, default: []].append(event)
        }

        return grouped.map { key, events in
            let avgElapsed = events.map(\.elapsedMs).reduce(0, +) / Double(max(events.count, 1))
            let anySuccess = events.contains(where: \.success)
            let parts = key.split(separator: "|", maxSplits: 2)
            return CompressedTracePattern(
                stateFingerprint: parts.count > 0 ? String(parts[0]) : "unknown",
                actionName: parts.count > 1 ? String(parts[1]) : "unknown",
                resultSuccess: anySuccess,
                occurrences: events.count,
                averageElapsedMs: avgElapsed
            )
        }
        .sorted { lhs, rhs in
            if lhs.occurrences == rhs.occurrences {
                return lhs.actionName < rhs.actionName
            }
            return lhs.occurrences > rhs.occurrences
        }
    }

    public func successRate(for patterns: [CompressedTracePattern]) -> Double {
        let total = patterns.reduce(0) { $0 + $1.occurrences }
        guard total > 0 else { return 0 }
        let successes = patterns.filter(\.resultSuccess).reduce(0) { $0 + $1.occurrences }
        return Double(successes) / Double(total)
    }

    private func patternKey(for event: TraceEvent) -> String {
        let stateFingerprint = [
            event.planningStateID ?? "no-state",
            event.agentKind ?? "unknown",
            event.domain ?? "no-domain",
        ].joined(separator: ":")
        return "\(stateFingerprint)|\(event.actionName)"
    }
}
