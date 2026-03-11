import Foundation
import Testing
@testable import OracleOS

@Suite("Trace Store")
struct TraceStoreTests {

    @Test("TraceStore writes JSONL events")
    func traceStoreWritesJSONL() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TraceStore(sessionID: "trace-session", baseDirectory: tempDirectory)

        let event = TraceEvent(
            sessionID: "trace-session",
            intent: ActionIntent(app: "Notes", name: "type", action: "type hello into Body", query: "Body"),
            result: ActionResult(success: true, message: nil, method: "click-then-type", verificationStatus: .passed),
            preObservationHash: "pre",
            postObservationHash: "post",
            verification: VerificationSummary(status: .passed, checks: []),
            elapsedMs: 100
        )

        let url = try store.append(event)
        let data = try Data(contentsOf: url)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")

        #expect(lines.count == 1)

        let lineData = Data(lines[0].utf8)
        let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any]

        #expect(object?["sessionID"] as? String == "trace-session")
        #expect(object?["preObservationHash"] as? String == "pre")
        #expect(object?["verification"] != nil)
    }
}
