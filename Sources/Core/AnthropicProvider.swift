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

        // Separate system message (Anthropic uses a top-level "system" field)
        var systemPrompt: String? = nil
        var conversationMessages: [[String: Any]] = []

        for message in messages {
            if message.role == .system {
                systemPrompt = message.content
            } else {
                conversationMessages.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": conversationMessages
        ]
        if let system = systemPrompt {
            body["system"] = system
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema.toAny()
                ]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]]
        else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.decodingError("Unexpected response shape: \(raw)")
        }

        // Check for tool_use blocks first
        var toolCalls: [ToolCall] = []
        var textParts: [String] = []

        for block in contentBlocks {
            guard let type = block["type"] as? String else { continue }
            switch type {
            case "tool_use":
                guard
                    let id = block["id"] as? String,
                    let name = block["name"] as? String
                else { continue }
                let inputAny = block["input"] ?? [String: Any]()
                let input = JSONValue.from(inputAny)
                toolCalls.append(ToolCall(id: id, name: name, input: input))
            case "text":
                if let text = block["text"] as? String {
                    textParts.append(text)
                }
            default:
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
