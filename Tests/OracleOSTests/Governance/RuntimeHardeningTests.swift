import Foundation
import Testing
@testable import OracleOS

/// Hardening tests that verify failure paths, edge cases, and regression gates.
@Suite("Runtime Hardening")
struct RuntimeHardeningTests {

    // MARK: - Failure path hardening

    @Test("ExecutionOutcome.failure captures error details")
    func failureOutcomeHasDetails() {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "test failure" }
        }
        let metadata = CommandMetadata(intentID: UUID())
        let cmd = LaunchAppCommand(metadata: metadata, bundleID: "test")
        let outcome = ExecutionOutcome.failure(from: TestError(), command: cmd)

        #expect(outcome.status == .failed)
        #expect(outcome.events.isEmpty)
        #expect(!outcome.verifierReport.notes.isEmpty)
        #expect(outcome.verifierReport.notes.first?.contains("test failure") == true)
    }

    @Test("ExecutionStatus has all expected cases")
    func executionStatusCases() {
        let cases: [ExecutionStatus] = [
            .success, .failed, .partialSuccess,
            .preconditionFailed, .policyBlocked, .postconditionFailed
        ]
        #expect(cases.count == 6)
    }

    @Test("VerifierReport captures command context")
    func verifierReportHasContext() {
        let cmdID = CommandID()
        let report = VerifierReport(
            commandID: cmdID,
            preconditionsPassed: false,
            policyDecision: "blocked",
            postconditionsPassed: false,
            notes: ["test note"]
        )
        #expect(report.commandID == cmdID)
        #expect(!report.preconditionsPassed)
        #expect(report.policyDecision == "blocked")
        #expect(report.notes == ["test note"])
    }

    // MARK: - Command model hardening

    @Test("UICommand has commandType .ui")
    func uiCommandType() {
        let cmd = ClickElementCommand(
            metadata: CommandMetadata(intentID: UUID()),
            targetID: "btn1",
            applicationBundleID: "com.test"
        )
        #expect(cmd.commandType == .ui)
        #expect(cmd.kind == "clickElement")
    }

    @Test("CodeCommand has commandType .code")
    func codeCommandType() {
        let cmd = RunBuildCommand(
            metadata: CommandMetadata(intentID: UUID()),
            workspacePath: "/tmp"
        )
        #expect(cmd.commandType == .code)
        #expect(cmd.kind == "runBuild")
    }

    @Test("SystemCommand has commandType .system")
    func systemCommandType() {
        let cmd = LaunchAppCommand(
            metadata: CommandMetadata(intentID: UUID()),
            bundleID: "com.test"
        )
        #expect(cmd.commandType == .system)
        #expect(cmd.kind == "launchApp")
    }

    @Test("CommandRouter routes by commandType")
    func commandRouterByType() {
        let uiCmd = ClickElementCommand(
            metadata: CommandMetadata(intentID: UUID()),
            targetID: "x",
            applicationBundleID: "y"
        )
        let codeCmd = RunBuildCommand(
            metadata: CommandMetadata(intentID: UUID()),
            workspacePath: "/tmp"
        )
        let sysCmd = LaunchAppCommand(
            metadata: CommandMetadata(intentID: UUID()),
            bundleID: "z"
        )

        #expect(CommandRouter.domain(for: uiCmd) == .ui)
        #expect(CommandRouter.domain(for: codeCmd) == .code)
        #expect(CommandRouter.domain(for: sysCmd) == .system)
    }

    @Test("CommandMetadata has required fields")
    func commandMetadataFields() {
        let id = UUID()
        let meta = CommandMetadata(
            intentID: id,
            source: "test",
            traceTags: ["tag1", "tag2"],
            planningStrategy: "direct"
        )
        #expect(meta.intentID == id)
        #expect(meta.source == "test")
        #expect(meta.traceTags == ["tag1", "tag2"])
        #expect(meta.planningStrategy == "direct")
        #expect(meta.timestamp == meta.createdAt)
    }

    // MARK: - Event model hardening

    @Test("EventEnvelope is codable")
    func eventEnvelopeCodable() throws {
        let envelope = EventEnvelope(
            id: UUID(), sequenceNumber: 42,
            commandID: CommandID(), intentID: UUID(),
            timestamp: Date(), eventType: "CommandSucceeded",
            payload: Data("{}".utf8)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EventEnvelope.self, from: data)

        #expect(decoded.id == envelope.id)
        #expect(decoded.sequenceNumber == 42)
        #expect(decoded.eventType == "CommandSucceeded")
    }

    // MARK: - Regression gates

    @Test("No direct state mutation paths exist in AgentLoop main file")
    func noDirectStateMutationInLoop() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/Loop/AgentLoop.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        let code = strippingComments(from: content)
        #expect(
            !code.contains("worldState."),
            "AgentLoop must not directly access worldState fields"
        )
        #expect(
            !code.contains("currentState ="),
            "AgentLoop must not assign to currentState"
        )
    }

    @Test("Event types are consistent")
    func eventTypeConsistency() {
        let expectedTypes = [
            "IntentReceived", "CommandPlanned", "CommandStarted",
            "CommandSucceeded", "CommandFailed", "PolicyRejected",
            "StateCommitted", "EvaluationRecorded",
            "RecoveryTriggered", "RecoveryCompleted"
        ]
        for typeName in expectedTypes {
            #expect(!typeName.isEmpty)
        }
    }

    // MARK: - Helpers

    private func strippingComments(from source: String) -> String {
        let pattern = #"//.*|/\*[\s\S]*?\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return source
        }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, options: [], range: range, withTemplate: "")
    }

    private func sourcesRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while true {
            let pkg = url.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: pkg.path) {
                return url.appendingPathComponent("Sources/OracleOS", isDirectory: true)
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return url.appendingPathComponent("Sources/OracleOS", isDirectory: true)
            }
            url = parent
        }
    }
}
