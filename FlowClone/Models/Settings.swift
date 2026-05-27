import Foundation
import Combine

class AppSettings: ObservableObject {
    private static let userDefaultsKey = "com.flowclone.settings"

    struct StoredSettings: Codable {
        var hotkey: Hotkey = .defaultHotkey
        var whisperModel: String = "base.en"
        var llmBaseURL: String = "http://localhost:4000"
        var llmModel: String = "gpt-4o"
        var personas: [Persona] = Persona.defaults
        var activePersonaID: UUID = Persona.defaults[0].id
    }

    @Published var hotkey: Hotkey {
        didSet { save() }
    }

    @Published var whisperModel: String {
        didSet { save() }
    }

    @Published var llmBaseURL: String {
        didSet { save() }
    }

    @Published var llmModel: String {
        didSet { save() }
    }

    @Published var personas: [Persona] {
        didSet { save() }
    }

    @Published var activePersonaID: UUID {
        didSet { save() }
    }

    var activePersona: Persona {
        personas.first(where: { $0.id == activePersonaID }) ?? personas[0]
    }

    private init(stored: StoredSettings) {
        self.hotkey = stored.hotkey
        self.whisperModel = stored.whisperModel
        self.llmBaseURL = stored.llmBaseURL
        self.llmModel = stored.llmModel
        self.personas = stored.personas
        self.activePersonaID = stored.activePersonaID
    }

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) else {
            return AppSettings(stored: StoredSettings())
        }
        return AppSettings(stored: stored)
    }

    private func save() {
        let stored = StoredSettings(
            hotkey: hotkey,
            whisperModel: whisperModel,
            llmBaseURL: llmBaseURL,
            llmModel: llmModel,
            personas: personas,
            activePersonaID: activePersonaID
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
