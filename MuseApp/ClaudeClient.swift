import Foundation

struct ClaudeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Appel direct de l'API Messages d'Anthropic (HTTP brut, pas de SDK Swift officiel).
struct ClaudeClient {
    static let model = "claude-opus-5-5"
    let apiKey: String

    func send(system: String, tools: [JSONValue], messages: [JSONValue]) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Si le modèle refuse une demande, l'API la relance automatiquement sur un autre modèle.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body: JSONValue = [
            "model": .string(Self.model),
            "max_tokens": 16000,
            "system": .string(system),
            "tools": .array(tools),
            "messages": .array(messages),
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            // Mise en cache automatique de l'historique : conversations plus rapides et moins chères.
            "cache_control": ["type": "ephemeral"],
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)

        guard status == 200, let json else {
            let detail = json?["error"]?["message"]?.string
                ?? String(data: data, encoding: .utf8) ?? "réponse illisible"
            switch status {
            case 401: throw ClaudeError(message: "Clé API invalide. Vérifie-la dans Réglages.")
            case 429: throw ClaudeError(message: "Trop de requêtes, réessaie dans un instant.")
            case 529, 500...599: throw ClaudeError(message: "Le service est surchargé (\(status)). Réessaie.")
            default: throw ClaudeError(message: "Erreur \(status) : \(detail)")
            }
        }
        return json
    }
}
