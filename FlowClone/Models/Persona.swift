import Foundation

struct Persona: Codable, Identifiable {
    var id: UUID
    var name: String
    var systemPrompt: String

    static let defaults: [Persona] = [
        Persona(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Casual",
            systemPrompt: "Write in a friendly, conversational tone. Use contractions. Keep it concise."
        ),
        Persona(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Professional",
            systemPrompt: "Write in clear, professional prose. No slang. Proper punctuation throughout."
        ),
        Persona(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Technical",
            systemPrompt: "Preserve technical terms exactly. Use precise language. Format code references in backticks."
        ),
    ]
}
