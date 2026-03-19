import Foundation
import Testing
@testable import OracleOS

/// Verifies the execution kernel trust boundary:
/// all execution must flow through VerifiedExecutor via RuntimeOrchestrator,
/// and legacy bypass paths (VerifiedActionExecutor, performAction) are removed.
@Suite("Execution Kernel Boundary")
@MainActor
struct ExecutionKernelBoundaryTests {

    // MARK: - ActionResult trust boundary contract

    @Test("ActionResult with executedThroughExecutor=true passes boundary contract")
    func stampedResultPassesBoundary() {
        let result = ActionResult(
            success: true,
            verified: true,
            executedThroughExecutor: true
        )
        #expect(result.executedThroughExecutor == true)
    }

    @Test("ActionResult with executedThroughExecutor=false fails boundary contract")
    func unstampedResultFailsBoundary() {
        let result = ActionResult(success: true, executedThroughExecutor: false)
        #expect(result.executedThroughExecutor == false)
    }

    // MARK: - round-trip through toDict / from(dict:)

    @Test("ActionResult executed_through_executor round-trips through toDict")
    func stampedRoundTripDict() {
        let original = ActionResult(success: true, executedThroughExecutor: true)
        let dict = original.toDict()
        let recovered = ActionResult.from(dict: dict)
        #expect(recovered?.executedThroughExecutor == true)
    }

    @Test("ActionResult executed_through_executor absent in dict defaults to false")
    func missingKeyDefaultsFalse() {
        let partial: [String: Any] = ["success": true]
        let result = ActionResult.from(dict: partial)
        #expect(result?.executedThroughExecutor == false)
    }

    // MARK: - ToolResult data contract

    @Test("ToolResult missing action_result key is detectable as bypass")
    func bareToolResultIsDetectable() {
        let bareResult = ToolResult(success: true, data: [:])
        let actionResultDict = bareResult.data?["action_result"] as? [String: Any]
        let stamped = actionResultDict != nil && actionResultDict?["executed_through_executor"] as? Bool == true
        #expect(stamped == false, "Bare ToolResult must be detected as an unstamped bypass")
    }

    @Test("ToolResult with stamped action_result passes detection")
    func stampedToolResultPassesDetection() {
        let actionResult = ActionResult(success: true, executedThroughExecutor: true)
        let result = ToolResult(success: true, data: ["action_result": actionResult.toDict()])
        let actionResultDict = result.data?["action_result"] as? [String: Any]
        let stamped = actionResultDict != nil && actionResultDict?["executed_through_executor"] as? Bool == true
        #expect(stamped == true)
    }

    // MARK: - Legacy removal verification

    @Test("VerifiedActionExecutor class is removed from ActionResult.swift")
    func verifiedActionExecutorRemoved() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/ActionResult.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        let codeWithoutComments = strippingComments(from: content)
        #expect(
            !codeWithoutComments.contains("class VerifiedActionExecutor"),
            "VerifiedActionExecutor class must be removed"
        )
    }

    @Test("performAction bridge is removed from ActionResult.swift")
    func performActionRemoved() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/ActionResult.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        let codeWithoutComments = strippingComments(from: content)
        #expect(
            !codeWithoutComments.contains("func performAction("),
            "performAction bridge must be removed"
        )
    }

    // MARK: - Helpers

    private func strippingComments(from source: String) -> String {
        let pattern = #"//.*|/\*[\s\S]*?\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return source
        }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(
            in: source,
            options: [],
            range: range,
            withTemplate: ""
        )
    }

    private func sourcesRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while true {
            let packageManifestURL = url.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifestURL.path) {
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
