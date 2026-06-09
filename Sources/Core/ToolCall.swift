import Foundation

/// A tool invocation requested by the model.
public struct ToolCall: Sendable {
    /// Provider-assigned identifier for this call (used to correlate tool results).
    public let id: String
    /// Name of the tool to invoke.
    public let name: String
    /// Decoded JSON arguments for the tool.
    public let input: JSONValue

    public init(id: String, name: String, input: JSONValue) {
        self.id = id
        self.name = name
        self.input = input
    }
}
