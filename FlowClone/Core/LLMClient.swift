import Foundation

class LLMClient {
    func cleanup(transcript: String, appName: String, persona: Persona, baseURL: String, model: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMError.invalidURL
        }

        let systemPrompt = """
            You are a voice dictation cleanup assistant. The user just dictated the following text using speech-to-text.

            Active application: \(appName)
            User persona: \(persona.name)
            Persona instructions: \(persona.systemPrompt)

            Your job:
            - Fix transcription errors, grammar, and punctuation
            - Format appropriately for the active application (e.g. casual tone in Slack, structured prose in Notion, no markdown in Terminal)
            - Apply the persona's tone and style
            - Return ONLY the cleaned text. No preamble, no explanation, no quotes.
            """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript],
            ],
            "max_tokens": 1000,
            "stream": false,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseFailed
        }

        return stripArtifacts(content)
    }

    private func stripArtifacts(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
           (result.hasPrefix("'") && result.hasSuffix("'")) {
            result = String(result.dropFirst().dropLast())
        }

        let preambles = [
            "Here's the cleaned text:",
            "Here is the cleaned text:",
            "Cleaned text:",
            "Here's the corrected text:",
            "Here is the corrected text:",
        ]
        for preamble in preambles {
            if result.hasPrefix(preamble) {
                result = String(result.dropFirst(preamble.count))
                break
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid LLM endpoint URL"
        case .invalidResponse: return "Invalid response from LLM"
        case .httpError(let code, let body): return "LLM request failed (\(code)): \(body)"
        case .parseFailed: return "Failed to parse LLM response"
        }
    }
}
