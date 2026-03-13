import Foundation

public struct LLMTargetCandidate: Sendable {
    public let elementDescription: String
    public let confidence: Double
    public let rationale: String

    public init(
        elementDescription: String,
        confidence: Double,
        rationale: String = ""
    ) {
        self.elementDescription = elementDescription
        self.confidence = confidence
        self.rationale = rationale
    }
}

public struct LLMTargetResolution: Sendable {
    public let candidates: [LLMTargetCandidate]
    public let llmUsed: Bool
    public let notes: [String]

    public init(
        candidates: [LLMTargetCandidate],
        llmUsed: Bool = false,
        notes: [String] = []
    ) {
        self.candidates = candidates
        self.llmUsed = llmUsed
        self.notes = notes
    }
}

public final class LLMTargetResolver: @unchecked Sendable {
    private let llmClient: LLMClient
    private let minimumConfidence: Double

    public init(
        llmClient: LLMClient,
        minimumConfidence: Double = 0.6
    ) {
        self.llmClient = llmClient
        self.minimumConfidence = minimumConfidence
    }

    public func resolve(
        goal: String,
        domSummary: String,
        visibleElements: [String]
    ) async -> LLMTargetResolution {
        let prompt = buildBrowserPrompt(
            goal: goal,
            domSummary: domSummary,
            visibleElements: visibleElements
        )
        let request = LLMRequest(
            prompt: prompt,
            modelTier: .browserReasoning,
            maxTokens: 512
        )

        do {
            let response = try await llmClient.complete(request)
            let candidates = parseCandidates(from: response.text, visibleElements: visibleElements)
            return LLMTargetResolution(
                candidates: candidates.filter { $0.confidence >= minimumConfidence },
                llmUsed: true,
                notes: ["LLM browser reasoning completed"]
            )
        } catch {
            return LLMTargetResolution(
                candidates: [],
                llmUsed: false,
                notes: ["LLM unavailable for browser target resolution"]
            )
        }
    }

    private func buildBrowserPrompt(
        goal: String,
        domSummary: String,
        visibleElements: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("User goal:")
        lines.append(goal)
        lines.append("")
        lines.append("Page summary:")
        lines.append(domSummary)
        lines.append("")
        lines.append("Visible elements:")
        for element in visibleElements.prefix(20) {
            lines.append("- \(element)")
        }
        lines.append("")
        lines.append("Choose the correct element to interact with and explain why.")
        lines.append("Format each candidate as:")
        lines.append("element: <description>")
        lines.append("confidence: <0.0 to 1.0>")
        lines.append("reason: <explanation>")
        return lines.joined(separator: "\n")
    }

    private func parseCandidates(from text: String, visibleElements: [String]) -> [LLMTargetCandidate] {
        var candidates: [LLMTargetCandidate] = []
        var currentElement = ""
        var currentConfidence = 0.5
        var currentReason = ""

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowered = trimmed.lowercased()

            if lowered.hasPrefix("element:") {
                if !currentElement.isEmpty {
                    candidates.append(LLMTargetCandidate(
                        elementDescription: currentElement,
                        confidence: currentConfidence,
                        rationale: currentReason
                    ))
                }
                currentElement = trimmed.dropFirst("element:".count)
                    .trimmingCharacters(in: .whitespaces)
                currentConfidence = 0.5
                currentReason = ""
            } else if lowered.hasPrefix("confidence:") {
                let value = trimmed.dropFirst("confidence:".count)
                    .trimmingCharacters(in: .whitespaces)
                currentConfidence = Double(value) ?? 0.5
            } else if lowered.hasPrefix("reason:") || lowered.hasPrefix("rationale:") {
                let prefix = lowered.hasPrefix("reason:") ? "reason:" : "rationale:"
                currentReason = trimmed.dropFirst(prefix.count)
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        if !currentElement.isEmpty {
            candidates.append(LLMTargetCandidate(
                elementDescription: currentElement,
                confidence: currentConfidence,
                rationale: currentReason
            ))
        }

        return candidates.sorted { $0.confidence > $1.confidence }
    }
}
