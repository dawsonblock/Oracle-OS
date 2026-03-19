import Foundation
import Testing
@testable import OracleOS

/// Tests AgentLoop scheduler behavior and boundary enforcement.
@Suite("AgentLoop Boundary")
struct AgentLoopTests {

    @Test("AgentLoop requires orchestrator")
    func agentLoopRequiresOrchestrator() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/Loop/AgentLoop.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(
            content.contains("orchestrator: any IntentAPI"),
            "AgentLoop must require an IntentAPI orchestrator"
        )
    }

    @Test("AgentLoop does not directly execute commands")
    func agentLoopDoesNotExecute() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/Loop/AgentLoop.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        let code = strippingComments(from: content)
        #expect(
            !code.contains("toolDispatcher"),
            "AgentLoop must not reference ToolDispatcher"
        )
        #expect(
            !code.contains("VerifiedExecutor("),
            "AgentLoop must not instantiate VerifiedExecutor"
        )
    }

    @Test("AgentLoop has scheduler mode")
    func agentLoopHasSchedulerMode() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/Loop/AgentLoop.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(
            content.contains("runAsScheduler"),
            "AgentLoop must have runAsScheduler method"
        )
    }

    @Test("AgentLoop has stop method")
    func agentLoopHasStop() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/Loop/AgentLoop.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(
            content.contains("func stop()"),
            "AgentLoop must have stop() method"
        )
    }

    @Test("IntentSource protocol exists")
    func intentSourceExists() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/Loop/IntentSource.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("protocol IntentSource"))
        #expect(content.contains("func next() async -> Intent?"))
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
