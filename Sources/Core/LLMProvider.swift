import Foundation

/// Abstraction over any LLM backend that supports chat completions and tool use.
public protocol LLMProvider: Sendable {
    /// Send a list of messages (and optional tools) and return the model's response.
    func complete(messages: [Message], tools: [Tool]) async throws -> LLMResponse
}
