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
        // Join multiple system messages with a blank line.
        var systemParts: [String] = []
        var conversationMessages: [AnthropicMessage] = []

        for message in messages {
            if message.role == .system {
                systemParts.append(message.content)
            } else {
                conversationMessages.append(AnthropicMessage(role: message.role.rawValue, content: message.content))
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

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
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

    private enum TypeKey: String, Decodable {
        case text
        case toolUse = "tool_use"
    }

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
