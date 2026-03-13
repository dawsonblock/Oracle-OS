import Foundation

public struct FailureClassification: Sendable {
    public let failureClass: FailureClass
    public let confidence: Double
    public let signals: [String]

    public init(
        failureClass: FailureClass,
        confidence: Double,
        signals: [String] = []
    ) {
        self.failureClass = failureClass
        self.confidence = min(max(confidence, 0), 1)
        self.signals = signals
    }
}

public enum FailureClassifier {

    public static func classify(
        errorDescription: String,
        context: FailureClassifierContext = FailureClassifierContext()
    ) -> FailureClassification {
        let lowered = errorDescription.lowercased()

        if lowered.contains("target") && (lowered.contains("missing") || lowered.contains("not found")) {
            return FailureClassification(
                failureClass: .targetMissing,
                confidence: contextBoosted(0.85, context: context, expected: .targetMissing),
                signals: ["target missing signal in error description"]
            )
        }
        if lowered.contains("ambiguous") {
            return FailureClassification(
                failureClass: .elementAmbiguous,
                confidence: contextBoosted(0.80, context: context, expected: .elementAmbiguous),
                signals: ["ambiguity signal in error description"]
            )
        }
        if lowered.contains("wrong") && lowered.contains("window") || lowered.contains("wrong focus") {
            return FailureClassification(
                failureClass: .wrongFocus,
                confidence: contextBoosted(0.75, context: context, expected: .wrongFocus),
                signals: ["wrong window/focus signal"]
            )
        }
        if lowered.contains("unexpected") && (lowered.contains("dialog") || lowered.contains("alert")) {
            return FailureClassification(
                failureClass: .unexpectedDialog,
                confidence: contextBoosted(0.80, context: context, expected: .unexpectedDialog),
                signals: ["unexpected dialog signal"]
            )
        }
        if lowered.contains("permission") || lowered.contains("denied") || lowered.contains("blocked") {
            return FailureClassification(
                failureClass: .permissionBlocked,
                confidence: contextBoosted(0.75, context: context, expected: .permissionBlocked),
                signals: ["permission blocked signal"]
            )
        }
        if lowered.contains("patch") && (lowered.contains("fail") || lowered.contains("reject")) {
            return FailureClassification(
                failureClass: .patchApplyFailed,
                confidence: contextBoosted(0.80, context: context, expected: .patchApplyFailed),
                signals: ["patch failure signal"]
            )
        }
        if lowered.contains("environment") || lowered.contains("mismatch") {
            return FailureClassification(
                failureClass: .environmentMismatch,
                confidence: contextBoosted(0.70, context: context, expected: .environmentMismatch),
                signals: ["environment mismatch signal"]
            )
        }
        if lowered.contains("workflow") && lowered.contains("replay") {
            return FailureClassification(
                failureClass: .workflowReplayFailure,
                confidence: contextBoosted(0.75, context: context, expected: .workflowReplayFailure),
                signals: ["workflow replay failure signal"]
            )
        }
        if lowered.contains("modal") || lowered.contains("blocking") {
            return FailureClassification(
                failureClass: .modalBlocking,
                confidence: contextBoosted(0.80, context: context, expected: .modalBlocking),
                signals: ["modal blocking signal"]
            )
        }
        if lowered.contains("build") && lowered.contains("fail") {
            return FailureClassification(
                failureClass: .buildFailed,
                confidence: contextBoosted(0.80, context: context, expected: .buildFailed),
                signals: ["build failure signal"]
            )
        }
        if lowered.contains("test") && lowered.contains("fail") {
            return FailureClassification(
                failureClass: .testFailed,
                confidence: contextBoosted(0.80, context: context, expected: .testFailed),
                signals: ["test failure signal"]
            )
        }
        if lowered.contains("navigate") || lowered.contains("navigation") {
            return FailureClassification(
                failureClass: .navigationFailed,
                confidence: contextBoosted(0.65, context: context, expected: .navigationFailed),
                signals: ["navigation failure signal"]
            )
        }

        return FailureClassification(
            failureClass: .actionFailed,
            confidence: 0.40,
            signals: ["no specific failure pattern matched"]
        )
    }

    private static func contextBoosted(
        _ base: Double,
        context: FailureClassifierContext,
        expected: FailureClass
    ) -> Double {
        var confidence = base
        if context.recentFailureClasses.contains(expected) {
            confidence = min(confidence + 0.05, 1.0)
        }
        return confidence
    }
}

public struct FailureClassifierContext: Sendable {
    public let app: String?
    public let domain: String?
    public let recentFailureClasses: [FailureClass]

    public init(
        app: String? = nil,
        domain: String? = nil,
        recentFailureClasses: [FailureClass] = []
    ) {
        self.app = app
        self.domain = domain
        self.recentFailureClasses = recentFailureClasses
    }
}
