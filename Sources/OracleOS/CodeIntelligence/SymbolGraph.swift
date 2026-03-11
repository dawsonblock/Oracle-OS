import Foundation

public struct RepositorySymbol: Codable, Sendable, Hashable {
    public let name: String
    public let kind: String
    public let path: String
    public let line: Int?

    public init(name: String, kind: String, path: String, line: Int? = nil) {
        self.name = name
        self.kind = kind
        self.path = path
        self.line = line
    }
}

public struct SymbolGraph: Codable, Sendable, Equatable {
    public let symbols: [RepositorySymbol]

    public init(symbols: [RepositorySymbol] = []) {
        self.symbols = symbols
    }
}
