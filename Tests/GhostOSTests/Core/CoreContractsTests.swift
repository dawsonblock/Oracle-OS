import CoreGraphics
import Foundation
import Testing
@testable import GhostOS

@MainActor
@Suite("Core Contracts")
struct CoreContractsTests {

    @Test("UnifiedElement codable round trip")
    func unifiedElementRoundTrip() throws {
        let element = UnifiedElement(
            id: "element-1",
            source: .ax,
            role: "AXButton",
            label: "Send",
            value: nil,
            frame: CGRect(x: 10, y: 20, width: 100, height: 40),
            enabled: true,
            visible: true,
            focused: false,
            confidence: 0.9
        )

        let encoded = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(UnifiedElement.self, from: encoded)

        #expect(decoded.id == element.id)
        #expect(decoded.label == element.label)
        #expect(decoded.frame == element.frame)
    }

    @Test("Observation hash is stable")
    func observationHashStable() {
        let element = UnifiedElement(id: "focused", source: .ax, label: "Body")
        let observation = Observation(
            app: "Notes",
            windowTitle: "Quick Note",
            url: nil,
            focusedElementID: "focused",
            elements: [element]
        )

        #expect(observation.stableHash() == observation.stableHash())
    }

    @Test("Action verifier checks focus and value")
    func actionVerifierChecks() {
        let send = UnifiedElement(id: "send", source: .ax, label: "Send")
        let field = UnifiedElement(
            id: "subject",
            source: .ax,
            label: "Subject",
            value: "Quarterly report",
            focused: true
        )
        let observation = Observation(
            app: "Chrome",
            windowTitle: "Compose",
            url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
            focusedElementID: "subject",
            elements: [send, field]
        )

        let summary = ActionVerifier.verify(
            post: observation,
            conditions: [
                .elementFocused("subject"),
                .elementValueEquals("subject", "Quarterly report"),
                .elementAppeared("send")
            ]
        )

        #expect(summary.status == .passed)
        #expect(summary.checks.allSatisfy { $0.passed })
    }

    @Test("Action verifier matches query-based focus, app, window, and URL")
    func actionVerifierChecksContextConditions() {
        let field = UnifiedElement(
            id: "subject-id",
            source: .ax,
            role: "AXTextField",
            label: "Subject",
            value: "Quarterly report",
            focused: true
        )
        let observation = Observation(
            app: "Google Chrome",
            windowTitle: "Compose - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
            focusedElementID: "subject-id",
            elements: [field]
        )

        let summary = ActionVerifier.verify(
            post: observation,
            conditions: [
                .elementFocused("Subject"),
                .appFrontmost("Chrome"),
                .windowTitleContains("Compose"),
                .urlContains("mail.google.com")
            ]
        )

        #expect(summary.status == .passed)
        #expect(summary.checks.allSatisfy { $0.passed })
    }

    @Test("Observation fusion prefers stronger sources and preserves confidence")
    func observationFusionPrefersStrongerSources() {
        let ax = UnifiedElement(
            id: "ax-send",
            source: .ax,
            role: "AXButton",
            label: "Send",
            frame: CGRect(x: 20, y: 30, width: 80, height: 24),
            confidence: 0.92
        )
        let cdp = UnifiedElement(
            id: "cdp-send",
            source: .cdp,
            role: "AXButton",
            label: "Send",
            frame: CGRect(x: 22, y: 31, width: 80, height: 24),
            confidence: 0.74
        )

        let fused = ObservationFusion.fuse(ax: [ax], cdp: [cdp], vision: [])

        #expect(fused.count == 1)
        #expect(fused[0].source == .fused)
        #expect(fused[0].label == "Send")
        #expect(fused[0].confidence == 0.92)
    }

    @Test("Trace event codable round trip")
    func traceEventRoundTrip() throws {
        let intent = ActionIntent(
            app: "Chrome",
            name: "click",
            action: "click Send",
            query: "Send",
            postconditions: [.elementAppeared("Message sent")]
        )
        let result = ActionResult(
            success: true,
            message: nil,
            method: "ax-native",
            verificationStatus: .passed,
            failureClass: nil
        )
        let verification = VerificationSummary(
            status: .passed,
            checks: [VerificationCheck(condition: .elementAppeared("Message sent"), passed: true, detail: nil)]
        )
        let event = TraceEvent(
            sessionID: "session-1",
            intent: intent,
            result: result,
            preObservationHash: "pre",
            postObservationHash: "post",
            verification: verification,
            elapsedMs: 123,
            failureClass: nil,
            artifacts: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TraceEvent.self, from: encoded)

        #expect(decoded.sessionID == event.sessionID)
        #expect(decoded.intent.name == "click")
        #expect(decoded.verification.status == VerificationStatus.passed)
    }
}
