import Foundation

public final class ProjectMemoryStore: @unchecked Sendable {
    public let projectRootURL: URL
    public let rootURL: URL
    public let databaseURL: URL
    public let residueURL: URL
    private let indexer: ProjectMemoryIndexer

    public init(projectRootURL: URL) throws {
        self.projectRootURL = projectRootURL
        self.rootURL = Self.rootURL(for: projectRootURL)
        self.databaseURL = Self.databaseURL(for: projectRootURL)
        self.residueURL = Self.residueURL(for: projectRootURL)
        self.indexer = try ProjectMemoryIndexer(databaseURL: databaseURL)
        try ensureStructure()
    }

    public static func rootURL(for projectRootURL: URL) -> URL {
        projectRootURL.appendingPathComponent("ProjectMemory", isDirectory: true)
    }

    public static func databaseURL(for projectRootURL: URL) -> URL {
        projectRootURL
            .appendingPathComponent(".oracle", isDirectory: true)
            .appendingPathComponent("project-memory.sqlite3", isDirectory: false)
    }

    public static func residueURL(for projectRootURL: URL) -> URL {
        projectRootURL
            .appendingPathComponent(".oracle", isDirectory: true)
            .appendingPathComponent("project-memory-episode", isDirectory: true)
    }

    public func ensureStructure() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for kind in ProjectMemoryKind.allCases where kind != .risk {
            try FileManager.default.createDirectory(
                at: rootURL.appendingPathComponent(kind.directoryName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(at: residueURL, withIntermediateDirectories: true)
    }

    public func syncIndex() {
        indexer.rebuild(from: rootURL)
    }

    public func writeDraft(_ draft: ProjectMemoryDraft) throws -> ProjectMemoryRef {
        try ensureStructure()
        let fileURL = draft.knowledgeClass == .episode
            ? residueFileURL(for: draft)
            : fileURL(for: draft)
        let record = ProjectMemoryRecord(
            id: fileURL.deletingPathExtension().lastPathComponent,
            kind: draft.kind,
            knowledgeClass: draft.knowledgeClass,
            status: .draft,
            title: draft.title,
            summary: draft.summary,
            affectedModules: draft.affectedModules,
            evidenceRefs: draft.evidenceRefs,
            sourceTraceIDs: draft.sourceTraceIDs,
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt,
            path: fileURL.path,
            body: renderMarkdown(for: draft, id: fileURL.deletingPathExtension().lastPathComponent)
        )
        try record.body.write(to: fileURL, atomically: true, encoding: .utf8)
        if draft.knowledgeClass != .episode {
            indexer.upsert(record)
        }
        return record.ref
    }

    public func writeOpenProblemDraft(
        title: String,
        summary: String,
        knowledgeClass: KnowledgeClass,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String
    ) throws -> ProjectMemoryRef {
        try writeDraft(
            ProjectMemoryDraft(
                kind: .openProblem,
                knowledgeClass: knowledgeClass,
                title: title,
                summary: summary,
                affectedModules: affectedModules,
                evidenceRefs: evidenceRefs,
                sourceTraceIDs: sourceTraceIDs,
                body: body
            )
        )
    }

    public func writeRejectedApproachDraft(
        title: String,
        summary: String,
        knowledgeClass: KnowledgeClass,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String
    ) throws -> ProjectMemoryRef {
        try writeDraft(
            ProjectMemoryDraft(
                kind: .rejectedApproach,
                knowledgeClass: knowledgeClass,
                title: title,
                summary: summary,
                affectedModules: affectedModules,
                evidenceRefs: evidenceRefs,
                sourceTraceIDs: sourceTraceIDs,
                body: body
            )
        )
    }

    public func writeKnownGoodPatternDraft(
        title: String,
        summary: String,
        knowledgeClass: KnowledgeClass,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String
    ) throws -> ProjectMemoryRef {
        try writeDraft(
            ProjectMemoryDraft(
                kind: .knownGoodPattern,
                knowledgeClass: knowledgeClass,
                title: title,
                summary: summary,
                affectedModules: affectedModules,
                evidenceRefs: evidenceRefs,
                sourceTraceIDs: sourceTraceIDs,
                body: body
            )
        )
    }

    public func writeArchitectureDecisionDraft(
        title: String,
        summary: String,
        knowledgeClass: KnowledgeClass,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String
    ) throws -> ProjectMemoryRef {
        try writeDraft(
            ProjectMemoryDraft(
                kind: .architectureDecision,
                knowledgeClass: knowledgeClass,
                title: title,
                summary: summary,
                affectedModules: affectedModules,
                evidenceRefs: evidenceRefs,
                sourceTraceIDs: sourceTraceIDs,
                body: body
            )
        )
    }

    public func query(
        text: String,
        modules: [String] = [],
        kinds: [ProjectMemoryKind] = [],
        limit: Int = 10
    ) -> [ProjectMemoryRef] {
        indexer.query(text: text, modules: modules, kinds: kinds, limit: limit)
    }

    private func fileURL(for draft: ProjectMemoryDraft) -> URL {
        let datePrefix = ISO8601DateFormatter().string(from: draft.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let slug = draft.title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let directory: URL
        if draft.kind == .risk {
            directory = rootURL
        } else {
            directory = rootURL.appendingPathComponent(draft.kind.directoryName, isDirectory: true)
        }
        return directory.appendingPathComponent("\(datePrefix)-\(slug).md", isDirectory: false)
    }

    private func residueFileURL(for draft: ProjectMemoryDraft) -> URL {
        let datePrefix = ISO8601DateFormatter().string(from: draft.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let slug = draft.title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return residueURL.appendingPathComponent("\(datePrefix)-\(slug).md", isDirectory: false)
    }

    private func renderMarkdown(for draft: ProjectMemoryDraft, id: String) -> String {
        let formatter = ISO8601DateFormatter()
        let header = [
            "# \(draft.kind.titlePrefix): \(draft.title)",
            "id: \(id)",
            "kind: \(draft.kind.rawValue)",
            "knowledge_class: \(draft.knowledgeClass.rawValue)",
            "status: \(ProjectMemoryStatus.draft.rawValue)",
            "summary: \(draft.summary)",
            "created_at: \(formatter.string(from: draft.createdAt))",
            "updated_at: \(formatter.string(from: draft.updatedAt))",
            "affected_modules: \(draft.affectedModules.joined(separator: ", "))",
            "evidence_refs: \(draft.evidenceRefs.joined(separator: ", "))",
            "source_trace_ids: \(draft.sourceTraceIDs.joined(separator: ", "))",
            "",
            "## Details",
            draft.body,
            "",
        ]
        return header.joined(separator: "\n")
    }
}
