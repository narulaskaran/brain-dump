import AppKit
import SwiftUI
import Core

// MARK: - SettingsView

struct SettingsView: View {

    // MARK: Provider

    @State private var selectedProvider: ProviderConfig.Provider
    @State private var baseURLString: String
    @State private var apiKey: String
    /// Either a value from `selectedProvider.commonModels` or the sentinel `"__custom__"`.
    @State private var modelSelection: String
    /// Text field value used when modelSelection == "__custom__".
    @State private var customModel: String

    // MARK: Vault

    @State private var vaultPathDisplay: String

    // MARK: Behaviour

    @State private var autoGroom: Bool

    // MARK: Errors

    @State private var keychainError: String?

    // MARK: Dismissal

    var onDone: (() -> Void)?

    // MARK: Init

    init(onDone: (() -> Void)? = nil) {
        self.onDone = onDone

        let config = ProviderConfig.load() ?? .defaultAnthropic
        _selectedProvider = State(initialValue: config.provider)
        _baseURLString = State(initialValue: config.baseURL.absoluteString)
        _apiKey = State(initialValue: KeychainHelper.load(key: "apiKey") ?? "")
        _autoGroom = State(initialValue: UserDefaults.standard.object(forKey: "autoGroom") as? Bool ?? true)

        let vaultURL = VaultPathManager.effectiveVaultURL()
        _vaultPathDisplay = State(initialValue: vaultURL.path)

        // Resolve model → picker selection vs custom text field
        let storedModel = config.model
        if config.provider.commonModels.contains(storedModel) {
            _modelSelection = State(initialValue: storedModel)
            _customModel = State(initialValue: "")
        } else {
            _modelSelection = State(initialValue: "__custom__")
            _customModel = State(initialValue: storedModel)
        }
    }

    // MARK: Body

    var body: some View {
        Form {
            // ---- LLM Provider ----
            Section("LLM Provider") {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(ProviderConfig.Provider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: selectedProvider) { _, new in
                    applyProviderDefaults(new)
                }

                if selectedProvider.showsBaseURLField {
                    TextField("Base URL", text: $baseURLString)
                        .textFieldStyle(.roundedBorder)
                }

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                if let keychainError {
                    Text(keychainError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                modelPickerView
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

    // MARK: - Model picker

    @ViewBuilder
    private var modelPickerView: some View {
        let models = selectedProvider.commonModels
        if models.isEmpty {
            // No known models (custom provider) — plain text field
            TextField("Model", text: $customModel)
                .textFieldStyle(.roundedBorder)
                .help("Enter any model identifier")
        } else {
            Picker("Model", selection: $modelSelection) {
                ForEach(models, id: \.self) { m in
                    Text(m).tag(m)
                }
                Divider()
                Text("Custom…").tag("__custom__")
            }

            if modelSelection == "__custom__" {
                TextField("Custom model ID", text: $customModel)
                    .textFieldStyle(.roundedBorder)
                    .help("Enter any model identifier supported by this provider")
            }
        }
    }

    // MARK: - Helpers

    private var effectiveModel: String {
        if selectedProvider.commonModels.isEmpty {
            return customModel
        }
        return modelSelection == "__custom__" ? customModel : modelSelection
    }

    private func applyProviderDefaults(_ provider: ProviderConfig.Provider) {
        baseURLString = provider.defaultBaseURL.absoluteString
        let defaultModel = provider.defaultModel
        if provider.commonModels.contains(defaultModel) {
            modelSelection = defaultModel
            customModel = ""
        } else {
            modelSelection = "__custom__"
            customModel = defaultModel
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
        do {
            try KeychainHelper.save(key: "apiKey", value: apiKey)
            keychainError = nil
        } catch {
            keychainError = "Could not save API key: \(error.localizedDescription)"
            return
        }

        let baseURL = URL(string: baseURLString) ?? selectedProvider.defaultBaseURL
        let config = ProviderConfig(provider: selectedProvider, baseURL: baseURL, model: effectiveModel)
        config.save()

        UserDefaults.standard.set(autoGroom, forKey: "autoGroom")

        onDone?()
    }
}
