import Foundation

public struct CodeQueryEngine: Sendable {
    private let search: CodeSearch
    private let impactAnalyzer: RepositoryChangeImpactAnalyzer

    public init(
        search: CodeSearch = CodeSearch(),
        impactAnalyzer: RepositoryChangeImpactAnalyzer = RepositoryChangeImpactAnalyzer()
    ) {
        self.search = search
        self.impactAnalyzer = impactAnalyzer
    }

    public func findSymbol(
        named name: String,
        in snapshot: RepositorySnapshot
    ) -> [SymbolNode] {
        snapshot.symbolGraph.nodes(named: name)
    }

    public func findCallers(
        of symbolID: String,
        in snapshot: RepositorySnapshot
    ) -> [SymbolNode] {
        let callerIDs = Set(snapshot.callGraph.callers(of: symbolID))
        return snapshot.symbolGraph.nodes.filter { callerIDs.contains($0.id) }
    }

    public func findDependencies(
        of file: String,
        in snapshot: RepositorySnapshot
    ) -> [String] {
        snapshot.dependencyGraph.directDependencies(of: file)
    }

    public func findTests(
        covering symbolID: String,
        in snapshot: RepositorySnapshot
    ) -> [RepositoryTest] {
        snapshot.testGraph.testsCovering(symbolID: symbolID)
    }

    public func findFilesReferencing(
        symbol name: String,
        in snapshot: RepositorySnapshot
    ) -> [String] {
        let normalized = name.lowercased()
        let referencedSymbols = snapshot.symbolGraph.nodes.filter { $0.name.lowercased() == normalized }
        let referenceFiles = referencedSymbols.flatMap { symbol in
            snapshot.callGraph.callers(of: symbol.id)
                .compactMap { snapshot.symbolGraph.node(id: $0)?.file }
        }
        let dependencyFiles = snapshot.dependencyGraph.edges
            .filter { $0.dependency.lowercased().contains(normalized) || ($0.toFile?.lowercased().contains(normalized) ?? false) }
            .map(\.sourcePath)
        return (referenceFiles + dependencyFiles).uniqued()
    }

    public func findLikelyRootCause(
        failingTest testSymbolID: String,
        in snapshot: RepositorySnapshot
    ) -> [RankedCodeCandidate] {
        let targetFiles = snapshot.testGraph.targetSymbolIDs(for: testSymbolID).compactMap { targetID in
            snapshot.symbolGraph.node(id: targetID)?.file
        }
        return impactAnalyzer.rankCandidates(targetFiles, in: snapshot)
    }

    public func findLikelyRootCause(
        failureDescription: String,
        in snapshot: RepositorySnapshot
    ) -> [RankedCodeCandidate] {
        let explicitPaths = extractExplicitPaths(from: failureDescription, snapshot: snapshot)
        let matchingTests = matchingTests(in: failureDescription, snapshot: snapshot)
        let testDrivenFiles = matchingTests.flatMap { test in
            if let symbolID = test.symbolID {
                return snapshot.testGraph.targetSymbolIDs(for: symbolID)
                    .compactMap { snapshot.symbolGraph.node(id: $0)?.file }
            }
            return []
        }
        let searchMatches = search.search(query: failureDescription, in: snapshot).map(\.path)
        let symbolMatches = likelySymbolFiles(from: failureDescription, snapshot: snapshot)
        let dependencyMatches = symbolMatches.flatMap { file in
            snapshot.dependencyGraph.reverseDependencies(of: file)
        }

        let preferredPaths = Set(explicitPaths + testDrivenFiles)
        let combined = (explicitPaths + testDrivenFiles + searchMatches + symbolMatches + dependencyMatches).uniqued()

        if combined.isEmpty, failureDescription.lowercased().contains("test") {
            let fallback = snapshot.testGraph.tests.prefix(5).map(\.path)
            return impactAnalyzer.rankCandidates(Array(fallback), in: snapshot)
        }

        return impactAnalyzer.rankCandidates(
            combined,
            in: snapshot,
            preferredPaths: preferredPaths
        )
    }

    public func impact(
        of file: String,
        in snapshot: RepositorySnapshot
    ) -> ChangeImpact {
        impactAnalyzer.impact(of: file, in: snapshot)
    }

    private func extractExplicitPaths(
        from text: String,
        snapshot: RepositorySnapshot
    ) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_./-]+\.(swift|ts|tsx|js|jsx|py)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        let paths = matches.compactMap { match -> String? in
            guard let pathRange = Range(match.range, in: text) else { return nil }
            return String(text[pathRange])
        }
        return paths.filter { candidate in
            snapshot.files.contains { $0.path == candidate }
        }.uniqued()
    }

    private func matchingTests(
        in text: String,
        snapshot: RepositorySnapshot
    ) -> [RepositoryTest] {
        let lowered = text.lowercased()
        return snapshot.testGraph.tests.filter { test in
            lowered.contains(test.name.lowercased())
                || lowered.contains(URL(fileURLWithPath: test.path).deletingPathExtension().lastPathComponent.lowercased())
        }
    }

    private func likelySymbolFiles(
        from text: String,
        snapshot: RepositorySnapshot
    ) -> [String] {
        let tokens = Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
                .map(String.init)
                .filter { $0.count > 2 }
        )
        return snapshot.symbolGraph.nodes
            .filter { node in
                tokens.contains { token in
                    node.name.lowercased().contains(token)
                }
            }
            .map(\.file)
            .uniqued()
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
