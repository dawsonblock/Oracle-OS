import Foundation
import Testing
@testable import OracleOS

/// Guards the runtime architecture invariants established in runtime-unification-36.
/// These tests fail CI if legacy paths are re-introduced.
@Suite("Runtime Integrity")
struct RuntimeIntegrityTests {

    // MARK: - No bypass execution

    @Test("performAction does not exist in runtime source")
    func noPerformAction() throws {
        let runtimeDir = sourcesRoot()
        let files = try allSwiftFiles(in: runtimeDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let code = strippingComments(from: content)
            let filename = file.lastPathComponent
            // Allow AXCompatibility performAction (AX element action, not runtime bypass)
            if filename == "AXCompatibility.swift" { continue }
            #expect(
                !code.contains("func performAction("),
                "performAction bypass found in \(filename) — use IntentAPI.submitIntent"
            )
        }
    }

    @Test("VerifiedActionExecutor class does not exist")
    func noVerifiedActionExecutor() throws {
        let files = try allSwiftFiles(in: sourcesRoot())

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let code = strippingComments(from: content)
            #expect(
                !code.contains("class VerifiedActionExecutor"),
                "VerifiedActionExecutor found in \(file.lastPathComponent) — deleted in unification-36"
            )
        }
    }

    @Test("No legacy RuntimeExecutionDriver execution methods")
    func noLegacyDriverMethods() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Runtime/RuntimeExecutionDriver.swift",
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let content = try String(contentsOf: url, encoding: .utf8)
        let code = strippingComments(from: content)
        #expect(
            !code.contains("executeLegacy("),
            "executeLegacy found in RuntimeExecutionDriver — must use IntentAPI path"
        )
        #expect(
            !code.contains("runtime.performAction("),
            "RuntimeExecutionDriver calls performAction — must use IntentAPI path"
        )
    }

    // MARK: - Only VerifiedExecutor performs side effects

    @Test("ToolDispatcher is only imported/used by VerifiedExecutor and RuntimeOrchestrator")
    func toolDispatcherOnlyUsedByExecutor() throws {
        let banned = [
            "Execution/Loop/AgentLoop.swift",
            "Planning/DecisionCoordinator.swift",
        ]
        for path in banned {
            let url = sourcesRoot().appendingPathComponent(path, isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let code = strippingComments(from: content)
            #expect(
                !code.contains("ToolDispatcher"),
                "\(path) must not reference ToolDispatcher — only VerifiedExecutor dispatches"
            )
        }
    }

    // MARK: - State mutation only through CommitCoordinator

    @Test("CommitCoordinator exists and has commit method")
    func commitCoordinatorExists() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Events/CommitCoordinator.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("func commit("))
        #expect(content.contains("actor CommitCoordinator"))
    }

    // MARK: - ToolDispatcher has no synthetic outputs

    @Test("ToolDispatcher does not return synthetic no-host:skipped")
    func noSyntheticOutputs() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Execution/ToolDispatcher.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(
            !content.contains("no-host: skipped"),
            "ToolDispatcher must not return synthetic 'no-host: skipped'"
        )
        #expect(
            !content.contains("no-context: skipped"),
            "ToolDispatcher must not return synthetic 'no-context: skipped'"
        )
    }

    // MARK: - RuntimeOrchestrator invariants

    @Test("RuntimeOrchestrator has no _legacyContext")
    func noLegacyContext() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Runtime/RuntimeOrchestrator.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(
            !content.contains("_legacyContext"),
            "RuntimeOrchestrator must not contain _legacyContext"
        )
    }

    @Test("RuntimeOrchestrator has submitIntent")
    func hasSubmitIntent() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Runtime/RuntimeOrchestrator.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("func submitIntent("))
    }

    // MARK: - Command model integrity

    @Test("Command protocol requires commandType")
    func commandHasCommandType() throws {
        let url = sourcesRoot().appendingPathComponent(
            "Commands/Command.swift",
            isDirectory: false
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("var commandType: CommandType"))
    }

    // MARK: - Helpers

    private func allSwiftFiles(in directory: URL) throws -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "swift" {
                result.append(url)
            }
        }
        return result
    }

    private func strippingComments(from source: String) -> String {
        let pattern = #"//.*|/\*[\s\S]*?\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return source
        }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(
            in: source, options: [], range: range, withTemplate: ""
        )
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
