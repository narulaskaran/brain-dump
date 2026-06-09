import Foundation

/// A single turn in an LLM conversation.
public struct Message: Sendable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    /// The content payload for a message.
    public enum Content: Sendable {
        /// Plain text content.
        case text(String)
        /// An assistant message that includes tool calls (for multi-turn tool use).
        case toolUse([ToolCall])
        /// A tool result message (role should be .tool or embedded in user turn).
        case toolResult(toolUseId: String, result: String)
    }

    public let role: Role
    public let content: Content

    // Convenience: plain text message (backward compat)
    public init(role: Role, content: String) {
        self.role = role
        self.content = .text(content)
    }

    public init(role: Role, toolUse calls: [ToolCall]) {
        self.role = role
        self.content = .toolUse(calls)
    }

    public init(role: Role, toolResultId: String, result: String) {
        self.role = role
        self.content = .toolResult(toolUseId: toolResultId, result: result)
    }

    // MARK: - Backward-compatible string accessor

    /// Returns text content if this is a plain-text message, nil otherwise.
    public var textContent: String? {
        if case .text(let s) = content { return s }
        return nil
    }
}
