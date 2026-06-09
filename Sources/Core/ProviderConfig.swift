import Foundation

/// Persisted configuration for the active LLM provider.
/// The API key is stored separately in the Keychain — never in this struct.
public struct ProviderConfig: Codable, Sendable {
    public enum Provider: String, Codable, Sendable {
        case anthropic
        case openai
    }

    public var provider: Provider
    /// Base URL for the provider's API.
    /// For Anthropic this field is ignored; the hard-coded endpoint is used instead.
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
            baseURL: URL(string: "https://api.anthropic.com")!,
            model: "claude-sonnet-4-6"
        )
    }

    public static var defaultOpenAI: ProviderConfig {
        ProviderConfig(
            provider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
            model: "gpt-4o"
        )
    }
}

// MARK: - UserDefaults persistence

private let userDefaultsKey = "com.braindump.providerConfig"

extension ProviderConfig {
    /// Load the saved config from `UserDefaults`, or `nil` if none has been saved.
    public static func load() -> ProviderConfig? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(ProviderConfig.self, from: data)
    }

    /// Persist this config to `UserDefaults`.
    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

// MARK: - Factory

/// Keychain key names for API keys.
public enum KeychainKeys {
    public static let anthropicAPIKey = "anthropic-api-key"
    public static let openAIAPIKey = "openai-api-key"
}

/// Instantiate the right `LLMProvider` for the given config, reading the API key from the Keychain.
public func makeLLMProvider(config: ProviderConfig) -> any LLMProvider {
    switch config.provider {
    case .anthropic:
        let key = KeychainHelper.load(key: KeychainKeys.anthropicAPIKey) ?? ""
        return AnthropicProvider(apiKey: key, model: config.model)
    case .openai:
        let key = KeychainHelper.load(key: KeychainKeys.openAIAPIKey) ?? ""
        return OpenAIProvider(baseURL: config.baseURL, apiKey: key, model: config.model)
    }
}
