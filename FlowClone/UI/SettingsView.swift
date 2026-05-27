import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            HotkeySettingsTab(settings: settings)
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }
            LLMSettingsTab(settings: settings)
                .tabItem {
                    Label("LLM", systemImage: "brain")
                }
        }
        .frame(width: 400, height: 320)
    }
}

struct HotkeySettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hold this key to record:")
                        .font(.subheadline)
                    HotkeyCaptureField(hotkey: $settings.hotkey)
                        .frame(height: 28)
                    Text("Click the field above, then press your desired hotkey combination.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

struct LLMSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKeyText: String = ""
    @State private var keySaved = false

    var body: some View {
        Form {
            Section("Endpoint") {
                TextField("Base URL", text: $settings.llmBaseURL)
                TextField("Model", text: $settings.llmModel)
            }

            Section("API Key") {
                SecureField("API Key", text: $apiKeyText)
                HStack {
                    Button("Save Key") {
                        guard !apiKeyText.isEmpty else { return }
                        try? KeychainHelper.upsert(key: apiKeyText)
                        keySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                    }
                    if keySaved {
                        Text("Saved")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }

            Section("Persona") {
                Picker("Active Persona", selection: $settings.activePersonaID) {
                    ForEach(settings.personas) { persona in
                        Text(persona.name).tag(persona.id)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            if let existing = try? KeychainHelper.read() {
                apiKeyText = existing
            }
        }
    }
}
