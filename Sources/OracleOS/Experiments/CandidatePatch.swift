import Foundation

public struct CandidatePatch: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let workspaceRelativePath: String
    public let content: String
    public let hypothesis: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        workspaceRelativePath: String,
        content: String,
        hypothesis: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.workspaceRelativePath = workspaceRelativePath
        self.content = content
        self.hypothesis = hypothesis
    }
}
