import Foundation

public enum RepositoryQuery {
    public static func files(matching symbol: String, in snapshot: RepositorySnapshot) -> [String] {
        let normalized = symbol.lowercased()
        return snapshot.symbolGraph.symbols
            .filter { $0.name.lowercased().contains(normalized) }
            .map(\.path)
            .uniqued()
    }

    public static func references(to symbol: String, in snapshot: RepositorySnapshot) -> [String] {
        let normalized = symbol.lowercased()
        return snapshot.dependencyGraph.edges
            .filter { $0.dependency.lowercased().contains(normalized) }
            .map(\.sourcePath)
            .uniqued()
    }

    public static func buildEntrypoints(in snapshot: RepositorySnapshot) -> [String] {
        var results: [String] = []
        if snapshot.files.contains(where: { $0.path == "Package.swift" }) {
            results.append("Package.swift")
        }
        if snapshot.files.contains(where: { $0.path == "package.json" }) {
            results.append("package.json")
        }
        results.append(contentsOf: snapshot.files.filter {
            $0.path.hasSuffix(".xcodeproj") || $0.path.hasSuffix(".xcworkspace")
        }.map(\.path))
        return results.uniqued()
    }

    public static func likelyFiles(
        for failureOutput: String,
        in snapshot: RepositorySnapshot
    ) -> [String] {
        let lines = failureOutput.split(separator: "\n").map(String.init)
        var matches: [String] = []

        for line in lines {
            if let swiftRange = line.range(of: #"[A-Za-z0-9_./-]+\.swift"#, options: .regularExpression) {
                matches.append(String(line[swiftRange]))
            }
            if let testRange = line.range(of: #"[A-Za-z0-9_./-]+Tests?\.swift"#, options: .regularExpression) {
                matches.append(String(line[testRange]))
            }
        }

        if matches.isEmpty {
            if failureOutput.lowercased().contains("test") {
                matches.append(contentsOf: snapshot.testGraph.tests.prefix(5).map(\.path))
            }
        }

        return matches
            .filter { path in snapshot.files.contains(where: { $0.path == path }) }
            .uniqued()
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
