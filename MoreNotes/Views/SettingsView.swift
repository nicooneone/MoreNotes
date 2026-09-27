import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var apiKey = KeychainStore.apiKey ?? ""
    @State private var settings = Settings.load()
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    HStack {
                        Button(testing ? "Testing…" : "Test connection") { test() }.disabled(testing || (apiKey.isEmpty && settings.proxyBaseURL.isEmpty))
                        Spacer()
                        if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
                    }
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Stored in the iOS Keychain on this device only. Get a key at console.anthropic.com. Alternatively, set a proxy URL below and leave the key empty; the proxy adds the key server-side.")
                }

                Section("Model") {
                    Picker("Model", selection: $settings.model) {
                        ForEach(Settings.availableModels) { m in Text(m.label).tag(m.id) }
                    }
                    Picker("Live tutor effort", selection: $settings.tutorEffort) {
                        ForEach(Settings.Effort.allCases) { e in Text(e.rawValue).tag(e) }
                    }
                    Picker("Chat & quiz effort", selection: $settings.chatEffort) {
                        ForEach(Settings.Effort.allCases) { e in Text(e.rawValue).tag(e) }
                    }
                }

                Section {
                    Toggle("Live Tutor on by default", isOn: Bindable(appState).liveTutorEnabled)
                    LabeledContent("Review after pencil rests") {
                        Text("\(Int(settings.tutorIdleSeconds)) s")
                    }
                    Slider(value: $settings.tutorIdleSeconds, in: 2...15, step: 1)
                    LabeledContent("Minimum gap between reviews") {
                        Text("\(Int(settings.tutorMinInterval)) s")
                    }
                    Slider(value: $settings.tutorMinInterval, in: 5...120, step: 5)
                    Toggle("Attach page image to chat messages", isOn: $settings.attachPageImageToChat)
                    Toggle("Index handwriting automatically", isOn: $settings.autoIndex)
                } header: {
                    Text("AI behaviour")
                } footer: {
                    Text("Every review sends an image of the page to Claude, so shorter gaps mean more API usage. Handwriting indexing runs on-device and is free.")
                }

                Section {
                    Toggle("Allow finger drawing", isOn: Bindable(appState).allowFingerDrawing)
                } header: {
                    Text("Pencil")
                } footer: {
                    Text("Off means fingers scroll and zoom while only the Apple Pencil or a Bluetooth stylus draws. Works with Apple Pencil (1st gen) on iPad 8th generation.")
                }

                Section {
                    TextField("https://your-proxy.example.com", text: $settings.proxyBaseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                } header: {
                    Text("Proxy (optional)")
                } footer: {
                    Text("Requests go to <proxy>/v1/messages with the same body. Use this to keep your API key off the device.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
        }
    }

    private func save() {
        KeychainStore.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.save()
        appState.settings = settings
    }

    private func test() {
        save()
        testing = true
        testResult = nil
        Task {
            do {
                let req = ClaudeRequest(model: settings.model, system: nil,
                                        messages: [ClaudeMessage(role: .user, text: "Reply with the single word OK.")],
                                        maxTokens: 50, effort: .low, cacheSystemPrompt: false)
                let r = try await ClaudeClient.shared.send(req, settings: settings)
                testResult = "Connected (\(r.model))"
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}
