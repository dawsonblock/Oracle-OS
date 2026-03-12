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
                confidence: 0.85,
                signals: ["target missing signal in error description"]
            )
        }
        if lowered.contains("ambiguous") {
            return FailureClassification(
                failureClass: .elementAmbiguous,
                confidence: 0.80,
                signals: ["ambiguity signal in error description"]
            )
        }
        if lowered.contains("wrong") && lowered.contains("window") || lowered.contains("wrong focus") {
            return FailureClassification(
                failureClass: .wrongFocus,
                confidence: 0.75,
                signals: ["wrong window/focus signal"]
            )
        }
        if lowered.contains("dialog") || lowered.contains("unexpected") && lowered.contains("alert") {
            return FailureClassification(
                failureClass: .unexpectedDialog,
                confidence: 0.80,
                signals: ["unexpected dialog signal"]
            )
        }
        if lowered.contains("permission") || lowered.contains("denied") || lowered.contains("blocked") {
            return FailureClassification(
                failureClass: .permissionBlocked,
                confidence: 0.75,
                signals: ["permission blocked signal"]
            )
        }
        if lowered.contains("patch") && (lowered.contains("fail") || lowered.contains("reject")) {
            return FailureClassification(
                failureClass: .patchApplyFailed,
                confidence: 0.80,
                signals: ["patch failure signal"]
            )
        }
        if lowered.contains("environment") || lowered.contains("mismatch") {
            return FailureClassification(
                failureClass: .environmentMismatch,
                confidence: 0.70,
                signals: ["environment mismatch signal"]
            )
        }
        if lowered.contains("workflow") && lowered.contains("replay") {
            return FailureClassification(
                failureClass: .verificationFailed,
                confidence: 0.65,
                signals: ["workflow replay failure signal"]
            )
        }
        if lowered.contains("modal") || lowered.contains("blocking") {
            return FailureClassification(
                failureClass: .modalBlocking,
                confidence: 0.80,
                signals: ["modal blocking signal"]
            )
        }
        if lowered.contains("build") && lowered.contains("fail") {
            return FailureClassification(
                failureClass: .buildFailed,
                confidence: 0.80,
                signals: ["build failure signal"]
            )
        }
        if lowered.contains("test") && lowered.contains("fail") {
            return FailureClassification(
                failureClass: .testFailed,
                confidence: 0.80,
                signals: ["test failure signal"]
            )
        }
        if lowered.contains("navigate") || lowered.contains("navigation") {
            return FailureClassification(
                failureClass: .navigationFailed,
                confidence: 0.65,
                signals: ["navigation failure signal"]
            )
        }

        return FailureClassification(
            failureClass: .actionFailed,
            confidence: 0.40,
            signals: ["no specific failure pattern matched"]
        )
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
