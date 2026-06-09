import Foundation

/// A tool that can be offered to an LLM provider.
public struct Tool: Sendable {
    public let name: String
    public let description: String
    /// JSON Schema for the tool's input, represented as a `JSONValue` object.
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}
