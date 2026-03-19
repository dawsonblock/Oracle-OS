import Foundation
import XCTest
@testable import OracleOS

final class RuntimeInvariantTests: XCTestCase {
    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return url }
            url = parent
        }
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    func test_no_bypass_execution_symbols() throws {
        let sourcesRoot = repositoryRoot().appendingPathComponent("Sources/OracleOS", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            XCTFail("Unable to enumerate sources")
            return
        }

        let forbidden = ["CodeActionGateway", "performAction(", "VerifiedActionExecutor", "ToolDispatcher"]
        var offenders: [String] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift",
                  let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  forbidden.contains(where: content.contains)
            else {
                continue
            }
            offenders.append(fileURL.lastPathComponent)
        }

        XCTAssertTrue(offenders.isEmpty, "Forbidden execution bypass symbols found: \(offenders)")
    }

    func test_loop_is_thin() throws {
        let loopSource = try read("Sources/OracleOS/Execution/Loop/AgentLoop+Run.swift")
        XCTAssertFalse(loopSource.contains("execute("), "AgentLoop+Run should not execute directly")
        XCTAssertFalse(loopSource.contains("decisionCoordinator"), "AgentLoop+Run should not decide directly")
        XCTAssertFalse(loopSource.contains("worldModel.reset("), "AgentLoop+Run should not mutate world state")
    }

    func test_runtime_orchestrator_has_single_pipeline_entry() throws {
        let orchestrator = try read("Sources/OracleOS/Runtime/RuntimeOrchestrator.swift")
        XCTAssertTrue(orchestrator.contains("verifiedExecutor.execute(command)"))
        XCTAssertFalse(orchestrator.contains("_legacyContext"))
        XCTAssertTrue(orchestrator.contains("commitCoordinator.commit(executionOutcome.events)"))
    }
}
