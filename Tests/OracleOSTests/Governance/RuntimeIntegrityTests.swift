import Foundation
import XCTest

final class RuntimeIntegrityTests: XCTestCase {
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

    private func swiftFiles(under directory: String) -> [URL] {
        let root = repositoryRoot().appendingPathComponent(directory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func test_removed_legacy_runtime_symbols_stay_absent() throws {
        let sourceFiles = swiftFiles(under: "Sources")
        let bannedPatterns = [
            "VerifiedActionExecutor",
            "RuntimeOrchestrator(context:",
            "_legacyContext",
        ]

        for url in sourceFiles {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let normalized = url.path.replacingOccurrences(of: "\\", with: "/")
            if normalized.contains("/Vendor/") || url.lastPathComponent == "RuntimeIntegrityTests.swift" { continue }
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "Legacy runtime symbol '\(pattern)' reappeared in \(url.path)"
                )
            }
        }
    }

    func test_runtime_execution_driver_has_no_legacy_route() throws {
        let path = repositoryRoot()
            .appendingPathComponent("Sources/OracleOS/Runtime/RuntimeExecutionDriver.swift")
        let content = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(content.contains("submitIntent("))
        XCTAssertFalse(content.contains("performAction("))
        XCTAssertFalse(content.contains("executeLegacy("))
    }

    func test_agent_loop_runtime_files_do_not_reset_world_model_directly() throws {
        let files = swiftFiles(under: "Sources/OracleOS/Execution/Loop")
        for url in files {
            let content = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                content.contains("worldModel.reset("),
                "Agent loop must not mutate committed world state directly: \(url.lastPathComponent)"
            )
        }
    }
}
