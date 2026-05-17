import SwiftUI

/// Settings view for configuring the AI service endpoint, API key, and timeout.
struct AISettingsView: View {

    // MARK: - State

    @State private var endpointText: String = ""
    @State private var apiKeyText: String = ""
    @State private var maskedAPIKey: String = ""
    @State private var timeoutSeconds: Double = AppConstants.defaultAITimeout
    @State private var showAPIKeyField: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveMessage: String?
    @State private var showSaveMessage: Bool = false

    /// The AI service actor for configuration.
    let aiService: AIService

    /// The encryption service for key masking.
    let encryptionService: EncryptionService

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
                    Text("AI Configuration")
                        .font(DesignSystem.Typography.headingMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("Configure the OpenAI-compatible API endpoint for PRD breakdown.")
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .padding(.bottom, DesignSystem.Spacing.spacing8)
            }

            Section("Endpoint") {
                TextField("API Endpoint URL", text: $endpointText)
                    .textFieldStyle(.roundedBorder)
                    .help("OpenAI-compatible API endpoint (e.g., https://openrouter.ai/api/v1)")

                Text("Enter the base URL for your OpenAI-compatible API provider.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            Section("API Key") {
                if showAPIKeyField {
                    SecureField("Enter API Key", text: $apiKeyText)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Cancel") {
                            apiKeyText = ""
                            showAPIKeyField = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                        Button("Save Key") {
                            Task { await saveAPIKey() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyText.isEmpty)
                    }
                } else {
                    HStack {
                        if maskedAPIKey.isEmpty {
                            Text("No API key configured")
                                .font(DesignSystem.Typography.bodyRegular)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        } else {
                            Text(maskedAPIKey)
                                .font(DesignSystem.Typography.monospace)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }

                        Spacer()

                        Button(maskedAPIKey.isEmpty ? "Set Key" : "Change Key") {
                            showAPIKeyField = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("Your API key is stored securely using AES-256-GCM encryption.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            Section("Timeout") {
                HStack {
                    Slider(value: $timeoutSeconds, in: 30...300, step: 10) {
                        Text("Request Timeout")
                    }

                    Text("\(Int(timeoutSeconds))s")
                        .font(DesignSystem.Typography.monospace)
                        .frame(width: 40, alignment: .trailing)
                }

                Text("Maximum time to wait for AI response (default: 120 seconds).")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            Section {
                HStack {
                    Spacer()

                    Button("Save Settings") {
                        Task { await saveSettings() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }

            if let message = saveMessage, showSaveMessage {
                Section {
                    Text(message)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Colors.success)
                }
            }
        }
        .formStyle(.grouped)
        .padding(DesignSystem.Spacing.spacing16)
        .task {
            await loadSettings()
        }
    }

    // MARK: - Actions

    private func loadSettings() async {
        let endpoint = await aiService.getEndpoint()
        endpointText = endpoint.absoluteString
        timeoutSeconds = await aiService.getTimeout()
        maskedAPIKey = await aiService.maskedAPIKey()
    }

    private func saveAPIKey() async {
        guard !apiKeyText.isEmpty else { return }
        isSaving = true

        do {
            try await aiService.storeAPIKey(apiKeyText)
            maskedAPIKey = await aiService.maskedAPIKey()
            apiKeyText = ""
            showAPIKeyField = false
            showSaveResult("API key saved successfully.")
        } catch {
            showSaveResult("Failed to save API key: \(error.localizedDescription)")
        }

        isSaving = false
    }

    private func saveSettings() async {
        isSaving = true

        if let url = URL(string: endpointText), !endpointText.isEmpty {
            await aiService.setEndpoint(url)
        }
        await aiService.setTimeout(timeoutSeconds)

        showSaveResult("Settings saved successfully.")
        isSaving = false
    }

    private func showSaveResult(_ message: String) {
        saveMessage = message
        showSaveMessage = true

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showSaveMessage = false
        }
    }
}
