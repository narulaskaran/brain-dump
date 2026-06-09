import Foundation

/// Persisted configuration for the active LLM provider.
/// The API key is stored separately in the Keychain — never in this struct.
public struct ProviderConfig: Codable, Sendable {
    public enum Provider: String, Codable, Sendable, CaseIterable {
        case anthropic
        case openai
        case openrouter
        case ollama
        case custom

        public var displayName: String {
            switch self {
            case .anthropic:  return "Anthropic"
            case .openai:     return "OpenAI"
            case .openrouter: return "OpenRouter"
            case .ollama:     return "Ollama"
            case .custom:     return "Custom"
            }
        }

        /// Whether to show an editable Base URL field for this provider.
        public var showsBaseURLField: Bool {
            switch self {
            case .anthropic, .openai: return false
            case .openrouter, .ollama, .custom: return true
            }
        }

        /// Pre-filled base URL (used to populate the field when provider is first selected).
        public var defaultBaseURL: URL {
            switch self {
            case .anthropic:  return URL(string: "https://api.anthropic.com")!
            case .openai:     return URL(string: "https://api.openai.com")!
            case .openrouter: return URL(string: "https://openrouter.ai/api")!
            case .ollama:     return URL(string: "http://localhost:11434")!
            case .custom:     return URL(string: "https://")!
            }
        }

        /// Suggested models shown in the picker. Empty = show a plain text field.
        public var commonModels: [String] {
            switch self {
            case .anthropic:
                return ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5"]
            case .openai:
                return ["gpt-4o", "gpt-4o-mini", "o1", "o3-mini"]
            case .openrouter:
                return [
                    "anthropic/claude-sonnet-4-6",
                    "anthropic/claude-opus-4-8",
                    "openai/gpt-4o",
                    "openai/gpt-4o-mini",
                    "meta-llama/llama-3.1-70b-instruct",
                    "google/gemini-pro-1.5",
                ]
            case .ollama:
                return ["llama3.2", "mistral", "phi3", "gemma2", "codellama"]
            case .custom:
                return []
            }
        }

        /// Default model to pre-fill when switching to this provider.
        public var defaultModel: String {
            commonModels.first ?? ""
        }
    }

    public var provider: Provider
    /// Base URL for the provider's API.
    /// For Anthropic and OpenAI this is fixed in the provider implementation;
    /// for all others it is sent as-is.
    public var baseURL: URL
    public var model: String

    public init(provider: Provider, baseURL: URL, model: String) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
    }

    // MARK: - Defaults

    public static var defaultAnthropic: ProviderConfig {
        ProviderConfig(
            provider: .anthropic,
            baseURL: Provider.anthropic.defaultBaseURL,
            model: Provider.anthropic.defaultModel
        )
    }

    public static var defaultOpenAI: ProviderConfig {
        ProviderConfig(
            provider: .openai,
            baseURL: Provider.openai.defaultBaseURL,
            model: Provider.openai.defaultModel
        )
    }
}

// MARK: - UserDefaults persistence

private let userDefaultsKey = "com.braindump.providerConfig"

extension ProviderConfig {
    public static func load() -> ProviderConfig? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(ProviderConfig.self, from: data)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

// MARK: - Factory

public enum KeychainKeys {
    public static let apiKey = "apiKey"
}

public func makeLLMProvider(config: ProviderConfig) -> any LLMProvider {
    let key = KeychainHelper.load(key: KeychainKeys.apiKey) ?? ""
    switch config.provider {
    case .anthropic:
        return AnthropicProvider(apiKey: key, model: config.model)
    case .openai, .openrouter, .ollama, .custom:
        return OpenAIProvider(baseURL: config.baseURL, apiKey: key, model: config.model)
    }
}
