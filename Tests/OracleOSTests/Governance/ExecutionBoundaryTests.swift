import Foundation
import Testing
@testable import OracleOS

@Suite("Execution Boundary")
struct ExecutionBoundaryTests {

    // MARK: - Planning files do not execute

    @Test("Planning files do not contain Process() or executionDriver references")
    func planningFilesDoNotExecute() throws {
        let planningDir = sourcesRoot()
            .appendingPathComponent("Agent")
            .appendingPathComponent("Planning")
        let files = try swiftFilesRecursive(in: planningDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("Process()"),
                "Planning file \(filename) must not spawn processes"
            )
            #expect(
                !content.contains("executionDriver"),
                "Planning file \(filename) must not reference executionDriver"
            )
        }
    }

    // MARK: - Reasoning files do not spawn processes or write files

    @Test("Reasoning files do not spawn processes or write files")
    func reasoningFilesDoNotExecute() throws {
        let reasoningDir = sourcesRoot().appendingPathComponent("Reasoning")
        let files = try swiftFilesRecursive(in: reasoningDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("Process()"),
                "Reasoning file \(filename) must not spawn processes"
            )
            #expect(
                !content.contains("FileManager.default.createFile"),
                "Reasoning file \(filename) must not write files directly"
            )
            #expect(
                !content.contains("write(to:"),
                "Reasoning file \(filename) must not write files directly"
            )
            #expect(
                !content.contains("write(toFile:"),
                "Reasoning file \(filename) must not write files directly"
            )
            #expect(
                !content.contains("FileHandle("),
                "Reasoning file \(filename) must not use FileHandle to write files directly"
            )
            #expect(
                !content.contains("FileHandle."),
                "Reasoning file \(filename) must not use FileHandle to write files directly"
            )
        }
    }

    // MARK: - Planner files do not directly mutate taskGraph

    @Test("Planner files do not directly mutate taskGraph")
    func plannerFilesDoNotMutateTaskGraph() throws {
        let planningDir = sourcesRoot()
            .appendingPathComponent("Agent")
            .appendingPathComponent("Planning")
        let files = try swiftFilesRecursive(in: planningDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("taskGraphStore.recordTransition"),
                "Planning file \(filename) must not directly call taskGraphStore.recordTransition"
            )
            #expect(
                !content.contains("taskGraphStore.addOrMergeNode"),
                "Planning file \(filename) must not directly call taskGraphStore.addOrMergeNode"
            )
        }
    }

    // MARK: - VisionPerception does not reference the planner

    @Test("VisionPerception does not reference the planner")
    func visionPerceptionDoesNotReferenceMainPlanner() throws {
        let visionURL = sourcesRoot().appendingPathComponent(
            "Vision/VisionPerception.swift",
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: visionURL.path) else { return }
        let content = try String(contentsOf: visionURL, encoding: .utf8)
        #expect(
            !content.contains("MainPlanner("),
            "VisionPerception.swift must not reference MainPlanner("
        )
        #expect(
            !content.contains("PlanGenerator("),
            "VisionPerception.swift must not reference PlanGenerator("
        )
    }

    // MARK: - Vision not in planner critical path

    @Test("Planning files do not reference vision perception")
    func visionNotInPlannerCriticalPath() throws {
        let planningDir = sourcesRoot()
            .appendingPathComponent("Agent")
            .appendingPathComponent("Planning")
        let reasoningDir = sourcesRoot().appendingPathComponent("Reasoning")

        let planningFiles = try swiftFilesRecursive(in: planningDir)
        let reasoningFiles = try swiftFilesRecursive(in: reasoningDir)

        let banned = ["VisionPerception", "VisionBridge", "oracle_parse_screen"]

        for file in planningFiles {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            for pattern in banned {
                #expect(
                    !content.contains(pattern),
                    "Planning file \(filename) must not reference '\(pattern)'"
                )
            }
        }

        let reasoningBanned = ["VisionPerception", "VisionBridge"]
        for file in reasoningFiles {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            for pattern in reasoningBanned {
                #expect(
                    !content.contains(pattern),
                    "Reasoning file \(filename) must not reference '\(pattern)'"
                )
            }
        }
    }

    // MARK: - Helpers

    private func swiftFilesRecursive(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var result: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" {
                result.append(url)
            }
        }
        return result
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
