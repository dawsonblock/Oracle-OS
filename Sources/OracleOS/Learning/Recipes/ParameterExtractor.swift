import Foundation

public struct ExtractedParameter: Sendable, Equatable {
    public let name: String
    public let kind: String
    public let values: [String]

    public init(name: String, kind: String, values: [String]) {
        self.name = name
        self.kind = kind
        self.values = values
    }
}

public enum ParameterExtractor {
    public static func extract(steps: [RecipeStep]) -> ([RecipeStep], [String]) {
        var params: Set<String> = []
        let updatedSteps = steps.map { step -> RecipeStep in
            var stepParams = step.params ?? [:]
            let actionExtraction = extractParameters(from: step.action)
            let noteExtraction = extractParameters(from: step.note)

            for parameter in actionExtraction + noteExtraction {
                params.insert(parameter.name)
                stepParams[parameter.name] = parameter.values.first ?? ""
            }

            let action = applyParameters(to: step.action, parameters: actionExtraction) ?? step.action
            let note = applyParameters(to: step.note, parameters: noteExtraction)

            return RecipeStep(
                id: step.id,
                action: action,
                target: step.target,
                params: stepParams.isEmpty ? nil : stepParams,
                waitAfter: step.waitAfter,
                note: note,
                onFailure: step.onFailure
            )
        }

        return (updatedSteps, Array(params).sorted())
    }

    public static func extract(from segments: [TraceSegment]) -> [ExtractedParameter] {
        let urls = uniqueValues(in: segments) { event in
            [event.actionTarget, event.actionText].compactMap { value in
                value.flatMap(firstURL(in:))
            }
        }
        let filePaths = uniqueValues(in: segments) { event in
            [event.workspaceRelativePath, event.actionTarget, event.actionText]
                .compactMap { $0 }
                .compactMap(firstFilePath(in:))
        }
        let branches = uniqueValues(in: segments) { event in
            [event.commandSummary, event.actionText].compactMap { value in
                value.flatMap(firstBranch(in:))
            }
        }
        let tests = uniqueValues(in: segments) { event in
            [event.actionText, event.commandSummary]
                .compactMap { $0 }
                .compactMap(firstTestName(in:))
        }
        let repositories = uniqueValues(in: segments) { event in
            [event.sandboxPath, event.workspaceRelativePath]
                .compactMap { $0 }
                .compactMap(firstRepositoryName(in:))
        }
        let labels = uniqueValues(in: segments) { event in
            [event.selectedElementLabel, event.actionTarget].compactMap { $0 }
        }

        return buildParameters(kind: "url", prefix: "url", values: urls)
            + buildParameters(kind: "file-path", prefix: "path", values: filePaths)
            + buildParameters(kind: "branch", prefix: "branch", values: branches)
            + buildParameters(kind: "test-name", prefix: "test", values: tests)
            + buildParameters(kind: "repository", prefix: "repository", values: repositories)
            + buildParameters(kind: "ui-label", prefix: "label", values: labels)
    }

    private static func extractParameters(from text: String?) -> [ExtractedParameter] {
        guard let text, !text.isEmpty else { return [] }
        return buildParameters(kind: "url", prefix: "url", values: orderedUnique(matches(in: text, using: #"https?://\S+"#)))
            + buildParameters(kind: "file-path", prefix: "path", values: orderedUnique(matches(in: text, using: #"(?:(?:[A-Za-z0-9_\-]+/)+[A-Za-z0-9_\-\.]+)"#)))
            + buildParameters(kind: "branch", prefix: "branch", values: orderedUnique(matches(in: text, using: #"(?:(?:feature|bugfix|hotfix|release)/[A-Za-z0-9_\-\.]+)"#)))
            + buildParameters(kind: "test-name", prefix: "test", values: orderedUnique(matches(in: text, using: #"(?:test[A-Za-z0-9_]+|[A-Za-z0-9_]+Tests(?:/[A-Za-z0-9_]+)?)"#)))
    }

    private static func applyParameters(to text: String?, parameters: [ExtractedParameter]) -> String? {
        guard var text else { return text }
        for parameter in parameters {
            for value in parameter.values {
                text = text.replacingOccurrences(of: value, with: "{{\(parameter.name)}}")
            }
        }
        return text
    }

    private static func buildParameters(kind: String, prefix: String, values: [String]) -> [ExtractedParameter] {
        let filtered = values.filter { !$0.isEmpty }
        guard !filtered.isEmpty else { return [] }
        return filtered.enumerated().map { index, value in
            ExtractedParameter(
                name: "\(prefix)_\(index)",
                kind: kind,
                values: [value]
            )
        }
    }

    private static func uniqueValues(
        in segments: [TraceSegment],
        extractor: (TraceEvent) -> [String]
    ) -> [String] {
        orderedUnique(
            segments.flatMap { segment in
                segment.events.flatMap(extractor)
            }
        )
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            seen.insert(value).inserted
        }
    }

    private static func matches(in text: String, using pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func firstURL(in text: String) -> String? {
        matches(in: text, using: #"https?://\S+"#).first
    }

    private static func firstFilePath(in text: String) -> String? {
        matches(in: text, using: #"(?:(?:[A-Za-z0-9_\-]+/)+[A-Za-z0-9_\-\.]+)"#).first
    }

    private static func firstBranch(in text: String) -> String? {
        matches(in: text, using: #"(?:(?:feature|bugfix|hotfix|release)/[A-Za-z0-9_\-\.]+)"#).first
    }

    private static func firstTestName(in text: String) -> String? {
        matches(in: text, using: #"(?:test[A-Za-z0-9_]+|[A-Za-z0-9_]+Tests(?:/[A-Za-z0-9_]+)?)"#).first
    }

    private static func firstRepositoryName(in text: String) -> String? {
        let sanitized = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !sanitized.isEmpty else { return nil }
        let components = sanitized.split(separator: "/")
        guard let last = components.last else { return nil }
        if last.contains(".") {
            return components.dropLast().last.map(String.init) ?? String(last)
        }
        return String(last)
    }
}
