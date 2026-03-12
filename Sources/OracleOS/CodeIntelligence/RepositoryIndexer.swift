import Foundation

public final class RepositoryIndexer: @unchecked Sendable {
    public init() {}

    public func index(workspaceRoot: URL) -> RepositorySnapshot {
        let buildTool = BuildToolDetector.detect(at: workspaceRoot)
        let files = enumerateFiles(workspaceRoot: workspaceRoot)
        let symbolGraph = SymbolGraph(symbols: extractSymbols(from: files, workspaceRoot: workspaceRoot))
        let dependencyGraph = DependencyGraph(edges: extractDependencies(from: files, workspaceRoot: workspaceRoot))
        let testGraph = TestGraph(tests: extractTests(from: files))
        let branch = currentBranch(workspaceRoot: workspaceRoot)
        let dirty = gitDirty(workspaceRoot: workspaceRoot)
        let id = [
            workspaceRoot.path,
            buildTool.rawValue,
            branch ?? "detached",
            dirty ? "dirty" : "clean",
        ].joined(separator: "|")

        return RepositorySnapshot(
            id: id,
            workspaceRoot: workspaceRoot.path,
            buildTool: buildTool,
            files: files,
            symbolGraph: symbolGraph,
            dependencyGraph: dependencyGraph,
            testGraph: testGraph,
            activeBranch: branch,
            isGitDirty: dirty
        )
    }

    private func enumerateFiles(workspaceRoot: URL) -> [RepositoryFile] {
        let resolvedRootPath = workspaceRoot.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [RepositoryFile] = []
        for case let fileURL as URL in enumerator {
            let resolvedFilePath = fileURL.resolvingSymlinksInPath().path
            let relative = resolvedFilePath.replacingOccurrences(of: resolvedRootPath + "/", with: "")
            if relative.hasPrefix(".build/") || relative.hasPrefix(".git/") || relative.hasPrefix("node_modules/") {
                continue
            }
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            files.append(RepositoryFile(path: relative, isDirectory: isDirectory))
        }
        return files.sorted { $0.path < $1.path }
    }

    private func extractSymbols(from files: [RepositoryFile], workspaceRoot: URL) -> [RepositorySymbol] {
        var results: [RepositorySymbol] = []
        let regexes: [(kind: String, pattern: String)] = [
            ("function", #"func\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            ("struct", #"struct\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            ("class", #"class\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            ("enum", #"enum\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            ("protocol", #"protocol\s+([A-Za-z_][A-Za-z0-9_]*)"#),
        ]

        for file in files where !file.isDirectory && (file.path.hasSuffix(".swift") || file.path.hasSuffix(".py") || file.path.hasSuffix(".js") || file.path.hasSuffix(".ts")) {
            guard let data = FileManager.default.contents(atPath: workspaceRoot.appendingPathComponent(file.path).path),
                  let text = String(data: data, encoding: .utf8)
            else {
                continue
            }

            for (kind, pattern) in regexes {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                for match in regex.matches(in: text, range: range) {
                    guard match.numberOfRanges > 1,
                          let nameRange = Range(match.range(at: 1), in: text)
                    else {
                        continue
                    }
                    let line = text[..<nameRange.lowerBound].split(separator: "\n").count + 1
                    results.append(
                        RepositorySymbol(
                            name: String(text[nameRange]),
                            kind: kind,
                            path: file.path,
                            line: line
                        )
                    )
                }
            }
        }
        return results.sorted { lhs, rhs in
            if lhs.path == rhs.path {
                return lhs.name < rhs.name
            }
            return lhs.path < rhs.path
        }
    }

    private func extractDependencies(from files: [RepositoryFile], workspaceRoot: URL) -> [DependencyEdge] {
        var edges: [DependencyEdge] = []
        let patterns = [
            #"import\s+([A-Za-z_][A-Za-z0-9_.]*)"#,
            #"from\s+([A-Za-z_][A-Za-z0-9_.]*)\s+import"#,
            #"require\(["']([^"']+)["']\)"#,
        ]

        for file in files where !file.isDirectory {
            guard let data = FileManager.default.contents(atPath: workspaceRoot.appendingPathComponent(file.path).path),
                  let text = String(data: data, encoding: .utf8)
            else {
                continue
            }
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                for match in regex.matches(in: text, range: range) {
                    guard match.numberOfRanges > 1,
                          let depRange = Range(match.range(at: 1), in: text)
                    else {
                        continue
                    }
                    edges.append(DependencyEdge(sourcePath: file.path, dependency: String(text[depRange])))
                }
            }
        }
        return edges
    }

    private func extractTests(from files: [RepositoryFile]) -> [RepositoryTest] {
        files.compactMap { file in
            guard !file.isDirectory else { return nil }
            let name = URL(fileURLWithPath: file.path).lastPathComponent
            guard name.localizedCaseInsensitiveContains("test") else { return nil }
            return RepositoryTest(name: name, path: file.path)
        }
    }

    private func currentBranch(workspaceRoot: URL) -> String? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "branch", "--show-current"]
        process.currentDirectoryURL = workspaceRoot
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func gitDirty(workspaceRoot: URL) -> Bool {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "status", "--porcelain"]
        process.currentDirectoryURL = workspaceRoot
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }
}
