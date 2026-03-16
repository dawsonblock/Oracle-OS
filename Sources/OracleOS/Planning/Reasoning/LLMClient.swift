import Foundation

public protocol LLMProvider: Sendable {
    /// Complete a prompt using the LLM with default request parameters.
    func complete(prompt: String) async throws -> String

    /// Complete a full `LLMRequest`, allowing providers to respect
    /// model tier, max token count and temperature.
    func complete(request: LLMRequest) async throws -> String
}

public extension LLMProvider {
    func complete(request: LLMRequest) async throws -> String {
        try await complete(prompt: request.prompt)
    }
}

public enum LLMModelTier: String, Sendable {
    case planning
    case codeRepair = "code_repair"
    case browserReasoning = "browser_reasoning"
    case recovery
    case memorySummarization = "memory_summarization"
    case metaReasoning = "meta_reasoning"
}

public struct LLMRequest: Sendable {
    public let prompt: String
    public let modelTier: LLMModelTier
    public let maxTokens: Int
    public let temperature: Double

    public init(
        prompt: String,
        modelTier: LLMModelTier = .planning,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) {
        self.prompt = prompt
        self.modelTier = modelTier
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public struct LLMResponse: Sendable {
    public let text: String
    public let modelTier: LLMModelTier
    public let tokenCount: Int
    public let latencyMs: Double

    public init(
        text: String,
        modelTier: LLMModelTier,
        tokenCount: Int = 0,
        latencyMs: Double = 0
    ) {
        self.text = text
        self.modelTier = modelTier
        self.tokenCount = tokenCount
        self.latencyMs = latencyMs
    }
}

public final class LLMClient: @unchecked Sendable {
    private let providers: [LLMModelTier: any LLMProvider]
    private let defaultProvider: (any LLMProvider)?
    private let maxRetries: Int
    private let lock = NSLock()
    private var requestCount: Int = 0
    private var totalTokens: Int = 0

    public init(
        providers: [LLMModelTier: any LLMProvider] = [:],
        defaultProvider: (any LLMProvider)? = nil,
        maxRetries: Int = 2
    ) {
        self.providers = providers
        // Fall back to OpenAIProvider when no explicit provider is given.
        // OpenAIProvider reads API key and endpoint from environment variables
        // and supports any OpenAI-compatible endpoint (Ollama, LM Studio, etc.).
        let resolved = defaultProvider ?? {
            let openAI = OpenAIProvider()
            return openAI.isConfigured ? openAI : nil
        }()
        self.defaultProvider = resolved
        self.maxRetries = maxRetries
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let provider = providers[request.modelTier] ?? defaultProvider
        guard let provider else {
            throw LLMClientError.noProvider
        }

        var lastError: Error?
        for _ in 0...maxRetries {
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let text = try await provider.complete(prompt: request.prompt)
                let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                let estimatedTokens = text.count / 4

                lock.lock()
                requestCount += 1
                totalTokens += estimatedTokens
                lock.unlock()

                return LLMResponse(
                    text: text,
                    modelTier: request.modelTier,
                    tokenCount: estimatedTokens,
                    latencyMs: latencyMs
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? LLMClientError.noProvider
    }

    public var diagnostics: LLMClientDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return LLMClientDiagnostics(
            requestCount: requestCount,
            totalTokens: totalTokens
        )
    }
}

public struct LLMClientDiagnostics: Sendable {
    public let requestCount: Int
    public let totalTokens: Int
}

public enum LLMClientError: Error, Sendable {
    case noProvider
    case rateLimited
    case timeout
    case transportError(String)
}
