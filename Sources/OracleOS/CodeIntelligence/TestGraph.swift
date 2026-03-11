import Foundation

public struct RepositoryTest: Codable, Sendable, Equatable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct TestGraph: Codable, Sendable, Equatable {
    public let tests: [RepositoryTest]

    public init(tests: [RepositoryTest] = []) {
        self.tests = tests
    }
}
