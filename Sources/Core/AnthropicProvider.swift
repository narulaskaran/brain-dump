import Foundation

/// LLM provider that calls the Anthropic Messages API.
public struct AnthropicProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public init(apiKey: String, model: String = "claude-sonnet-4-6", maxTokens: Int = 4096) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    public func complete(messages: [Message], tools: [Tool]) async throws -> LLMResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Separate system messages (Anthropic uses a top-level "system" field).
        var systemParts: [String] = []
        var conversationMessages: [AnthropicMessage] = []

        for message in messages {
            if message.role == .system {
                if case .text(let s) = message.content { systemParts.append(s) }
                continue
            }

            switch message.content {
            case .text(let s):
                conversationMessages.append(AnthropicMessage(
                    role: message.role.rawValue,
                    content: .string(s)
                ))

            case .toolUse(let calls):
                // Assistant message with tool_use blocks
                let blocks: [AnthropicContentBlock] = calls.map { call in
                    AnthropicContentBlock.toolUse(AnthropicToolUseBlock(
                        id: call.id, name: call.name, input: call.input
                    ))
                }
                conversationMessages.append(AnthropicMessage(
                    role: "assistant",
                    content: .blocks(blocks)
                ))

            case .toolResult(let toolUseId, let result):
                // Tool result must be wrapped as a user message with a tool_result block
                let block = AnthropicContentBlock.toolResult(AnthropicToolResultBlock(
                    toolUseId: toolUseId, content: result
                ))
                // Anthropic requires tool_result blocks in a user-role message.
                // If the last conversation message is already a user-role tool_result
                // accumulator, append to it; otherwise create a new user message.
                if var last = conversationMessages.last, last.role == "user",
                   case .blocks(let existing) = last.content {
                    let updated = existing + [block]
                    conversationMessages[conversationMessages.count - 1] = AnthropicMessage(
                        role: "user", content: .blocks(updated)
                    )
                } else {
                    conversationMessages.append(AnthropicMessage(
                        role: "user",
                        content: .blocks([block])
                    ))
                }
            }
        }

        let systemPrompt: String? = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")

        let toolPayloads: [AnthropicTool] = tools.map { tool in
            AnthropicTool(name: tool.name, description: tool.description, inputSchema: tool.inputSchema)
        }

        let body = AnthropicRequestBody(
            model: model,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: conversationMessages,
            tools: toolPayloads.isEmpty ? nil : toolPayloads
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(URLError(.badServerResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF-8 body>"
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try parseResponse(data: data)
    }

    // MARK: - Response parsing

    private func parseResponse(data: Data) throws -> LLMResponse {
        let decoded: AnthropicResponseBody
        do {
            decoded = try JSONDecoder().decode(AnthropicResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingError(error.localizedDescription)
        }

        var toolCalls: [ToolCall] = []
        var textParts: [String] = []

        for block in decoded.content {
            switch block {
            case .toolUse(let toolUse):
                toolCalls.append(ToolCall(id: toolUse.id, name: toolUse.name, input: toolUse.input))
            case .text(let textBlock):
                textParts.append(textBlock.text)
            case .unknown:
                break
            }
        }

        if !toolCalls.isEmpty {
            return .toolCalls(toolCalls)
        }
        if !textParts.isEmpty {
            return .text(textParts.joined())
        }
        throw LLMError.noContent
    }
}

// MARK: - Private request types

private struct AnthropicRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
    }
}

private enum AnthropicContentBlock: Encodable {
    case text(String)
    case toolUse(AnthropicToolUseBlock)
    case toolResult(AnthropicToolResultBlock)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let s):
            var c = encoder.container(keyedBy: GenericCodingKeys.self)
            try c.encode("text", forKey: .init("type"))
            try c.encode(s, forKey: .init("text"))
        case .toolUse(let block):
            try block.encode(to: encoder)
        case .toolResult(let block):
            try block.encode(to: encoder)
        }
    }
}

private enum AnthropicMessageContent: Encodable {
    case string(String)
    case blocks([AnthropicContentBlock])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .blocks(let blocks):
            var c = encoder.singleValueContainer()
            try c.encode(blocks)
        }
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: AnthropicMessageContent
}

private struct AnthropicToolUseBlock: Encodable {
    let id: String
    let name: String
    let input: JSONValue

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: GenericCodingKeys.self)
        try c.encode("tool_use", forKey: .init("type"))
        try c.encode(id, forKey: .init("id"))
        try c.encode(name, forKey: .init("name"))
        try c.encode(input, forKey: .init("input"))
    }
}

private struct AnthropicToolResultBlock: Encodable {
    let toolUseId: String
    let content: String

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: GenericCodingKeys.self)
        try c.encode("tool_result", forKey: .init("type"))
        try c.encode(toolUseId, forKey: .init("tool_use_id"))
        try c.encode(content, forKey: .init("content"))
    }
}

private struct AnthropicTool: Encodable {
    let name: String
    let description: String
    /// Raw JSON schema — encoded as-is by forwarding to JSONValue's own encoder.
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

// MARK: - Private response types

private struct AnthropicResponseBody: Decodable {
    let content: [ContentBlock]
}

private enum ContentBlock: Decodable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)
        switch type_ {
        case "text":
            self = .text(try TextBlock(from: decoder))
        case "tool_use":
            self = .toolUse(try ToolUseBlock(from: decoder))
        default:
            self = .unknown
        }
    }
}

private struct TextBlock: Decodable {
    let text: String
}

private struct ToolUseBlock: Decodable {
    let id: String
    let name: String
    let input: JSONValue
}

// MARK: - Generic coding key helper

private struct GenericCodingKeys: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}
