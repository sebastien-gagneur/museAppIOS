import Foundation

/// Un élément affiché dans la conversation.
struct ChatItem: Identifiable {
    enum Kind {
        case user(String)
        case assistant(String)
        case activity(String)            // ex. « Recherche sur le web… »
        case approval(ApprovalRequest)   // en attente de validation
        case approvalResult(String, Bool)
        case error(String)
    }
    let id = UUID()
    let kind: Kind
}

@MainActor
final class AgentViewModel: ObservableObject {
    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var isRunning = false
    @Published var pendingApprovalID: UUID?

    private var messages: [JSONValue] = []
    private let tools = AgentTools()
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var task: Task<Void, Never>?

    private let systemPrompt = """
    Tu es l'assistant personnel de l'utilisateur, dans son app iPhone. Tu réponds en français, \
    de façon brève et concrète. Tu agis plutôt que d'expliquer : utilise les outils pour consulter \
    ou modifier l'agenda et les rappels, préparer des e-mails, chercher des contacts, des lieux \
    ou des informations sur le web, et ouvrir l'onglet muse.ai de l'app.

    Règles :
    - Les créations (événements, rappels) sont soumises à la validation de l'utilisateur par l'app : \
    appelle simplement l'outil, sans redemander la permission dans le texte. Si l'utilisateur refuse, \
    n'insiste pas et demande ce qu'il veut changer.
    - Un e-mail n'est jamais envoyé sans l'utilisateur : compose_email ouvre une fenêtre qu'il relit et envoie lui-même.
    - Pour trouver l'adresse d'une personne, cherche d'abord dans les contacts. N'invente jamais une adresse e-mail ni un numéro.
    - Chaque message de l'utilisateur commence par un bloc [Contexte] donnant la date, l'heure et le fuseau : \
    sers-t'en pour interpréter « demain », « vendredi », etc., et donne toujours les dates avec ce fuseau.
    - Tu ne peux pas effectuer d'achats ni de réservations en ligne : propose les liens, numéros ou lieux pour que l'utilisateur le fasse.
    """

    func reset() {
        task?.cancel()
        resolveApproval(false)
        messages = []
        items = []
        isRunning = false
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        guard let key = Keychain.apiKey else {
            items.append(ChatItem(kind: .error("Ajoute ta clé API Anthropic dans l'onglet Réglages.")))
            return
        }
        items.append(ChatItem(kind: .user(text)))
        messages.append(["role": "user", "content": [["type": "text", "text": .string(Self.context() + "\n\n" + text)]]])
        isRunning = true
        task = Task { await runLoop(client: ClaudeClient(apiKey: key)); isRunning = false }
    }

    func resolveApproval(_ approved: Bool) {
        pendingApprovalID = nil
        approvalContinuation?.resume(returning: approved)
        approvalContinuation = nil
    }

    // MARK: - Boucle de l'agent

    private func runLoop(client: ClaudeClient) async {
        for _ in 0..<25 {
            if Task.isCancelled { return }
            let response: JSONValue
            do {
                response = try await client.send(system: systemPrompt, tools: AgentTools.definitions, messages: messages)
            } catch {
                if Task.isCancelled { return }
                items.append(ChatItem(kind: .error(error.localizedDescription)))
                rollbackDanglingUserTurn()
                return
            }
            if Task.isCancelled { return }

            let content = response["content"]?.array ?? []
            let stop = response["stop_reason"]?.string ?? ""
            // L'historique garde la réponse telle quelle (blocs de réflexion compris).
            messages.append(["role": "assistant", "content": .array(content)])

            for block in content {
                switch block["type"]?.string {
                case "text":
                    if let t = block["text"]?.string, !t.isEmpty { appendAssistantText(t) }
                case "server_tool_use":
                    let q = block["input"]?["query"]?.string ?? ""
                    items.append(ChatItem(kind: .activity("Recherche web : \(q)")))
                default: break
                }
            }

            switch stop {
            case "tool_use":
                var results: [JSONValue] = []
                for block in content where block["type"]?.string == "tool_use" {
                    let id = block["id"]?.string ?? ""
                    let name = block["name"]?.string ?? ""
                    let input = block["input"] ?? [:]
                    let output = await execute(name: name, input: input)
                    if Task.isCancelled { return }
                    var result: [String: JSONValue] = ["type": "tool_result", "tool_use_id": .string(id),
                                                       "content": .string(output.text)]
                    if output.isError { result["is_error"] = true }
                    results.append(.object(result))
                }
                messages.append(["role": "user", "content": .array(results)])
            case "pause_turn":
                continue   // recherche web longue : on relance, le serveur reprend où il en était
            case "refusal":
                items.append(ChatItem(kind: .error("Cette demande a été refusée par le modèle.")))
                return
            case "max_tokens":
                items.append(ChatItem(kind: .error("Réponse coupée (trop longue).")))
                return
            default:
                return
            }
        }
        items.append(ChatItem(kind: .error("L'agent s'est arrêté après trop d'étapes.")))
    }

    private func execute(name: String, input: JSONValue) async -> ToolOutput {
        if let request = tools.approvalNeeded(name: name, input: input) {
            let item = ChatItem(kind: .approval(request))
            items.append(item)
            pendingApprovalID = item.id
            let approved = await withCheckedContinuation { approvalContinuation = $0 }
            items.append(ChatItem(kind: .approvalResult(request.title, approved)))
            guard approved else { return ToolOutput(text: "L'utilisateur a refusé cette action.") }
        } else {
            items.append(ChatItem(kind: .activity(Self.activityLabel(name: name, input: input))))
        }
        return await tools.run(name: name, input: input)
    }

    private func appendAssistantText(_ text: String) {
        // Fusionne les textes consécutifs de l'assistant dans une même bulle.
        if case .assistant(let previous)? = items.last?.kind {
            items[items.count - 1] = ChatItem(kind: .assistant(previous + "\n\n" + text))
        } else {
            items.append(ChatItem(kind: .assistant(text)))
        }
    }

    /// Après une erreur réseau, retire le dernier tour incomplet pour pouvoir réessayer proprement.
    private func rollbackDanglingUserTurn() {
        while let last = messages.last {
            let isPlainUserText = last["role"]?.string == "user"
                && last["content"]?.array?.first?["type"]?.string == "text"
            messages.removeLast()
            if isPlainUserText { break }
        }
    }

    private static func activityLabel(name: String, input: JSONValue) -> String {
        switch name {
        case "list_events": return "Consultation de l'agenda"
        case "list_reminders": return "Consultation des rappels"
        case "compose_email": return "Préparation d'un e-mail"
        case "search_contacts": return "Recherche du contact « \(input["query"]?.string ?? "") »"
        case "search_places": return "Recherche de lieux : \(input["query"]?.string ?? "")"
        case "open_directions": return "Ouverture de l'itinéraire"
        case "call_phone": return "Appel téléphonique"
        case "open_muse": return "Ouverture de muse.ai"
        default: return name
        }
    }

    private static func context() -> String {
        let now = Date()
        let tz = TimeZone.current
        let date = now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()
            .locale(Locale(identifier: "fr_FR")))
        return "[Contexte : \(date), fuseau \(tz.identifier), maintenant = \(AgentTools.iso(now))]"
    }
}
