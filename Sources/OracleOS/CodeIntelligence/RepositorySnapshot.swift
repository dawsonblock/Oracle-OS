import Foundation

public struct RepositoryFile: Codable, Sendable, Equatable {
    public let path: String
    public let isDirectory: Bool

    public init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
    }
}

public struct RepositorySnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let workspaceRoot: String
    public let buildTool: BuildTool
    public let files: [RepositoryFile]
    public let symbolGraph: SymbolGraph
    public let dependencyGraph: DependencyGraph
    public let testGraph: TestGraph
    public let activeBranch: String?
    public let isGitDirty: Bool
    public let indexedAt: Date

    public init(
        id: String,
        workspaceRoot: String,
        buildTool: BuildTool,
        files: [RepositoryFile],
        symbolGraph: SymbolGraph,
        dependencyGraph: DependencyGraph,
        testGraph: TestGraph,
        activeBranch: String?,
        isGitDirty: Bool,
        indexedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceRoot = workspaceRoot
        self.buildTool = buildTool
        self.files = files
        self.symbolGraph = symbolGraph
        self.dependencyGraph = dependencyGraph
        self.testGraph = testGraph
        self.activeBranch = activeBranch
        self.isGitDirty = isGitDirty
        self.indexedAt = indexedAt
    }
}
