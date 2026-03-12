import Foundation

public enum MemoryScorer {
    public static func rankingBias(
        control: KnownControl,
        failureCount: Int,
        now: Date = Date()
    ) -> Double {
        guard MemoryPromotionPolicy.allowsDurableBias(
            successes: control.successCount,
            failures: failureCount
        ) else {
            return 0
        }

        let base = min(log(Double(control.successCount) + 1) * 0.05, 0.15)
        return base * MemoryDecayPolicy.freshnessMultiplier(since: control.lastUsed, now: now)
    }

    public static func commandBias(
        successes: Int,
        failures: Int
    ) -> Double {
        guard MemoryPromotionPolicy.allowsDurableBias(
            successes: successes,
            failures: failures
        ) else {
            return 0
        }

        return min(log(Double(successes) + 1) * 0.05, 0.15)
    }

    public static func fixPatternScore(
        pattern: FixPattern,
        now: Date = Date()
    ) -> Double {
        guard MemoryPromotionPolicy.allowsDurableBias(
            successes: pattern.successCount,
            failures: pattern.failureCount
        ) else {
            return 0
        }

        let base = Double(pattern.successCount) - Double(pattern.failureCount) * 0.5
        return max(0, base) * MemoryDecayPolicy.freshnessMultiplier(
            since: pattern.lastAppliedAt,
            now: now
        )
    }
}
