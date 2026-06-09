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
        let endpoint = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let openAIMessages: [[String: Any]] = messages.map { message in
            ["role": message.role.rawValue, "content": message.content]
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": openAIMessages
        ]

        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.inputSchema.toAny()
                    ] as [String: Any]
                ]
            }
            body["tool_choice"] = "auto"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let messageDict = firstChoice["message"] as? [String: Any]
        else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.decodingError("Unexpected response shape: \(raw)")
        }

        // Check for tool_calls
        if let toolCallsRaw = messageDict["tool_calls"] as? [[String: Any]], !toolCallsRaw.isEmpty {
            var toolCalls: [ToolCall] = []
            for tc in toolCallsRaw {
                guard
                    let id = tc["id"] as? String,
                    let functionDict = tc["function"] as? [String: Any],
                    let name = functionDict["name"] as? String,
                    let argumentsString = functionDict["arguments"] as? String,
                    let argumentsData = argumentsString.data(using: .utf8),
                    let argumentsAny = try? JSONSerialization.jsonObject(with: argumentsData)
                else { continue }
                let input = JSONValue.from(argumentsAny)
                toolCalls.append(ToolCall(id: id, name: name, input: input))
            }
            if !toolCalls.isEmpty {
                return .toolCalls(toolCalls)
            }
        }

        // Fall back to text content
        if let content = messageDict["content"] as? String, !content.isEmpty {
            return .text(content)
        }

        throw LLMError.noContent
    }
}
