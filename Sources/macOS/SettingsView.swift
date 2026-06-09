import AppKit
import SwiftUI
import Core

// MARK: - SettingsView

struct SettingsView: View {

    // MARK: Provider

    @State private var selectedProvider: ProviderConfig.Provider
    @State private var baseURLString: String
    @State private var apiKey: String
    @State private var model: String

    // MARK: Vault

    @State private var vaultPathDisplay: String

    // MARK: Behaviour

    @State private var autoGroom: Bool

    // MARK: Dismissal

    var onDone: (() -> Void)?

    // MARK: Init

    init(onDone: (() -> Void)? = nil) {
        self.onDone = onDone

        let config = ProviderConfig.load() ?? .defaultAnthropic
        _selectedProvider = State(initialValue: config.provider)
        _baseURLString = State(initialValue: config.baseURL.absoluteString)
        _model = State(initialValue: config.model)
        _apiKey = State(initialValue: KeychainHelper.load(key: "apiKey") ?? "")
        _autoGroom = State(initialValue: UserDefaults.standard.object(forKey: "autoGroom") as? Bool ?? true)

        let vaultURL = VaultPathManager.effectiveVaultURL()
        _vaultPathDisplay = State(initialValue: vaultURL.path)
    }

    // MARK: Body

    var body: some View {
        Form {
            // ---- LLM Provider ----
            Section("LLM Provider") {
                Picker("Provider", selection: $selectedProvider) {
                    Text("Anthropic").tag(ProviderConfig.Provider.anthropic)
                    Text("OpenAI-compatible").tag(ProviderConfig.Provider.openai)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedProvider) { _, newValue in
                    applyProviderDefaults(newValue)
                }

                if selectedProvider == .openai {
                    TextField("Base URL", text: $baseURLString)
                        .textFieldStyle(.roundedBorder)
                        .help("e.g. https://api.openai.com")
                }

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .help(modelPlaceholder)
            }

            // ---- Vault ----
            Section("Vault") {
                HStack {
                    Text(vaultPathDisplay)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") {
                        chooseVaultFolder()
                    }
                }
            }

            // ---- Hotkey ----
            Section("Hotkey") {
                LabeledContent("Current binding", value: "⌘⇧I")
                    .foregroundStyle(.secondary)
            }

            // ---- Behaviour ----
            Section("Behaviour") {
                Toggle("Auto-groom after filing", isOn: $autoGroom)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)

        HStack {
            Spacer()
            Button("Done") {
                saveAndDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding([.horizontal, .bottom])
    }

    // MARK: - Helpers

    private var modelPlaceholder: String {
        selectedProvider == .anthropic ? "claude-sonnet-4-6" : "gpt-4o"
    }

    private func applyProviderDefaults(_ provider: ProviderConfig.Provider) {
        switch provider {
        case .anthropic:
            baseURLString = "https://api.anthropic.com"
            if model.isEmpty || model == "gpt-4o" { model = "claude-sonnet-4-6" }
        case .openai:
            baseURLString = "https://api.openai.com"
            if model.isEmpty || model == "claude-sonnet-4-6" { model = "gpt-4o" }
        }
    }

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Vault Folder"
        panel.message = "Select the folder where BrainDump will store your ideas."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try VaultPathManager.storeBookmark(for: url)
            vaultPathDisplay = url.path
        } catch {
            print("[BrainDump] Failed to store vault bookmark: \(error)")
        }
    }

    private func saveAndDismiss() {
        // Persist API key to Keychain
        try? KeychainHelper.save(key: "apiKey", value: apiKey)

        // Build and persist ProviderConfig
        let baseURL = URL(string: baseURLString) ?? URL(string: "https://api.anthropic.com")!
        let config = ProviderConfig(provider: selectedProvider, baseURL: baseURL, model: model)
        config.save()

        // Persist behaviour settings
        UserDefaults.standard.set(autoGroom, forKey: "autoGroom")

        onDone?()
    }
}
