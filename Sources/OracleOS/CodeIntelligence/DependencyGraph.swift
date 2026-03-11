import Foundation

public struct DependencyEdge: Codable, Sendable, Equatable {
    public let sourcePath: String
    public let dependency: String

    public init(sourcePath: String, dependency: String) {
        self.sourcePath = sourcePath
        self.dependency = dependency
    }
}

public struct DependencyGraph: Codable, Sendable, Equatable {
    public let edges: [DependencyEdge]

    public init(edges: [DependencyEdge] = []) {
        self.edges = edges
    }
}
