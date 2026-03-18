import Foundation
import Testing
@testable import OracleOS

/// Verifies the single execution spine invariant:
///   Intent → Planner → Command → VerifiedExecutor → Events → CommitCoordinator
///
/// These tests scan source files for patterns that would bypass the execution spine.
@Suite("Execution Spine")
struct ExecutionSpineTests {

    // MARK: - ToolDispatcher callable only from VerifiedExecutor

    @Test("ToolDispatcher.dispatch is not called outside VerifiedExecutor")
    func toolDispatcherOnlyCalledFromExecutor() throws {
        let executionDir = sourcesRoot().appendingPathComponent("Execution")
        let allSwift = try swiftFilesRecursive(in: executionDir)

        for file in allSwift {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent

            // Only VerifiedExecutor.swift should call toolDispatcher.dispatch
            guard filename != "VerifiedExecutor.swift",
                  filename != "ToolDispatcher.swift"
            else { continue }

            // Allow test files to reference dispatch for testing purposes
            guard !file.path.contains("/Tests/") else { continue }

            #expect(
                !content.contains("toolDispatcher.dispatch("),
                "\(filename) should not call toolDispatcher.dispatch directly — route through VerifiedExecutor"
            )
        }
    }

    // MARK: - Build/test commands use /usr/bin/env

    @Test("Build and test commands use /usr/bin/env not bare executables")
    func buildTestCommandsUseEnv() throws {
        let dispatcherPath = sourcesRoot()
            .appendingPathComponent("Execution")
            .appendingPathComponent("ToolDispatcher.swift")
        let content = try String(contentsOf: dispatcherPath, encoding: .utf8)

        // The dispatcher should route build/test through /usr/bin/env
        #expect(
            content.contains("executable: \"/usr/bin/env\""),
            "ToolDispatcher should use /usr/bin/env for build/test commands"
        )
        // It must not use bare "swift" as executable (fails WorkspaceRunner allowlist)
        let lines = content.split(separator: "\n")
        for line in lines {
            if line.contains("executable:") && line.contains("\"swift\"") {
                // Only allowed inside comments
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                #expect(
                    trimmed.hasPrefix("//"),
                    "ToolDispatcher must not use bare 'swift' as executable — use '/usr/bin/env' instead"
                )
            }
        }
    }

    // MARK: - RuntimeOrchestrator evaluate is not a stub

    @Test("RuntimeOrchestrator.evaluate is implemented, not a stub")
    func evaluateIsImplemented() throws {
        let orchestratorPath = sourcesRoot()
            .appendingPathComponent("Runtime")
            .appendingPathComponent("RuntimeOrchestrator.swift")
        let content = try String(contentsOf: orchestratorPath, encoding: .utf8)

        #expect(
            !content.contains("/* critic loop stub */"),
            "RuntimeOrchestrator.evaluate should be implemented, not a stub"
        )
        #expect(
            content.contains("EvaluationResult"),
            "RuntimeOrchestrator.evaluate should return EvaluationResult"
        )
    }

    // MARK: - Helpers

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

    private func swiftFilesRecursive(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                result.append(fileURL)
            }
        }
        return result
    }
}
