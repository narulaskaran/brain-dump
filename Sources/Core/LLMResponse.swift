import Foundation

/// The response returned by an LLM provider after a completion request.
public enum LLMResponse: Sendable {
    /// The model returned a text reply.
    case text(String)
    /// The model requested one or more tool calls.
    case toolCalls([ToolCall])
}
