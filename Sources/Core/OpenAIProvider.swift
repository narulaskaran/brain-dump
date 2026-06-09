import Foundation

/// LLM provider that calls any OpenAI-compatible `/v1/chat/completions` endpoint.
/// Works with OpenAI, OpenRouter, Ollama, and other compatible services.
public struct OpenAIProvider: LLMProvider {
    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let maxTokens: Int

    public init(
        baseURL: URL = URL(string: "https://api.openai.com")!,
        apiKey: String,
        model: String = "gpt-4o",
        maxTokens: Int = 4096
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    public func complete(messages: [Message], tools: [Tool]) async throws -> LLMResponse {
        let endpoint = baseURL.appending(path: "v1/chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let openAIMessages: [OpenAIMessage] = messages.map { message in
            OpenAIMessage(role: message.role.rawValue, content: message.content)
        }

        let toolPayloads: [OpenAITool]? = tools.isEmpty ? nil : tools.map { tool in
            OpenAITool(
                type: "function",
                function: OpenAIFunction(
                    name: tool.name,
                    description: tool.description,
                    parameters: tool.inputSchema
                )
            )
        }

        let body = OpenAIRequestBody(
            model: model,
            maxTokens: maxTokens,
            messages: openAIMessages,
            tools: toolPayloads,
            toolChoice: toolPayloads != nil ? "auto" : nil
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(URLError(.badServerResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF-8 body>"
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: bodyString)
        }

        return try parseResponse(data: data)
    }

    // MARK: - Response parsing

    private func parseResponse(data: Data) throws -> LLMResponse {
        let decoded: OpenAIResponseBody
        do {
            decoded = try JSONDecoder().decode(OpenAIResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingError(error.localizedDescription)
        }

        guard let firstChoice = decoded.choices.first else {
            throw LLMError.noContent
        }

        let message = firstChoice.message

        // Check for tool_calls
        if let toolCallsRaw = message.toolCalls, !toolCallsRaw.isEmpty {
            var toolCalls: [ToolCall] = []
            for tc in toolCallsRaw {
                let argumentsData = Data(tc.function.arguments.utf8)
                let input: JSONValue
                do {
                    input = try JSONDecoder().decode(JSONValue.self, from: argumentsData)
                } catch {
                    throw LLMError.decodingError(error.localizedDescription)
                }
                toolCalls.append(ToolCall(id: tc.id, name: tc.function.name, input: input))
            }
            if !toolCalls.isEmpty {
                return .toolCalls(toolCalls)
            }
        }

        // Fall back to text content
        if let content = message.content, !content.isEmpty {
            return .text(content)
        }

        throw LLMError.noContent
    }
}

// MARK: - Private request types

private struct OpenAIRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [OpenAIMessage]
    let tools: [OpenAITool]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case tools
        case toolChoice = "tool_choice"
    }
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAITool: Encodable {
    let type: String
    let function: OpenAIFunction
}

private struct OpenAIFunction: Encodable {
    let name: String
    let description: String
    /// Raw JSON schema forwarded via JSONValue's own encoder.
    let parameters: JSONValue
}

// MARK: - Private response types

private struct OpenAIResponseBody: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIResponseMessage
}

private struct OpenAIResponseMessage: Decodable {
    let content: String?
    let toolCalls: [OpenAIToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

private struct OpenAIToolCall: Decodable {
    let id: String
    let function: OpenAIToolCallFunction
}

private struct OpenAIToolCallFunction: Decodable {
    let name: String
    let arguments: String
}
