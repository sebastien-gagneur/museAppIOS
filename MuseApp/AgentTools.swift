import Foundation
import EventKit
import Contacts
import MapKit
import MessageUI
import UIKit

/// Résultat d'un outil renvoyé à Claude.
struct ToolOutput {
    var text: String
    var isError = false
}

/// Description d'une action à faire valider par l'utilisateur.
struct ApprovalRequest {
    let title: String
    let details: String
}

/// Définitions des outils exposés à Claude, et leur exécution sur l'iPhone.
@MainActor
final class AgentTools {
    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()
    private var mailDelegate: MailDelegate?

    // MARK: - Définitions envoyées à l'API

    static let definitions: [JSONValue] = [
        ["type": "web_search_20260209", "name": "web_search", "max_uses": 5],
        tool("list_events",
             "Liste les événements de l'agenda de l'iPhone entre deux dates.",
             ["start": dateProp("Début de la période"), "end": dateProp("Fin de la période")],
             required: ["start", "end"]),
        tool("create_event",
             "Crée un événement dans l'agenda. L'utilisateur doit valider avant la création (l'app s'en charge).",
             ["title": str("Titre"), "start": dateProp("Début"), "end": dateProp("Fin"),
              "location": str("Lieu (facultatif)"), "notes": str("Notes (facultatif)")],
             required: ["title", "start", "end"]),
        tool("list_reminders",
             "Liste les rappels non terminés de l'app Rappels.",
             [:], required: []),
        tool("create_reminder",
             "Crée un rappel. L'utilisateur doit valider avant la création (l'app s'en charge).",
             ["title": str("Intitulé"), "due": dateProp("Échéance (facultatif)"), "notes": str("Notes (facultatif)")],
             required: ["title"]),
        tool("compose_email",
             "Prépare un e-mail et ouvre la fenêtre d'envoi : l'utilisateur relit, puis envoie ou annule lui-même.",
             ["to": ["type": "array", "items": ["type": "string"], "description": "Adresses des destinataires"],
              "subject": str("Objet"), "body": str("Corps du message, en texte brut")],
             required: ["to", "subject", "body"]),
        tool("search_contacts",
             "Cherche des contacts par nom dans le carnet d'adresses (téléphones et e-mails).",
             ["query": str("Nom ou partie du nom")], required: ["query"]),
        tool("search_places",
             "Cherche des lieux, commerces ou adresses avec Plans (nom, adresse, téléphone, site web).",
             ["query": str("Ex. : 'restaurant italien Grenoble'")], required: ["query"]),
        tool("open_directions",
             "Ouvre l'itinéraire vers une destination dans l'app Plans.",
             ["destination": str("Adresse ou nom du lieu")], required: ["destination"]),
        tool("call_phone",
             "Lance un appel téléphonique (iOS demande confirmation à l'utilisateur).",
             ["number": str("Numéro de téléphone")], required: ["number"]),
        tool("open_muse",
             "Affiche l'onglet muse.ai de l'app, éventuellement sur une page précise de muse.ai.",
             ["url": str("Adresse https://muse.ai/... (facultatif)")], required: []),
    ]

    private static func tool(_ name: String, _ description: String,
                             _ properties: [String: JSONValue], required: [String]) -> JSONValue {
        ["name": .string(name), "description": .string(description),
         "input_schema": ["type": "object", "properties": .object(properties),
                          "required": .array(required.map { .string($0) })]]
    }
    private static func str(_ d: String) -> JSONValue { ["type": "string", "description": .string(d)] }
    private static func dateProp(_ d: String) -> JSONValue {
        ["type": "string", "description": .string(d + ", au format ISO 8601 avec fuseau, ex. 2026-11-15T14:00:00+01:00")]
    }

    // MARK: - Validation

    /// Renvoie la demande de validation si l'outil modifie quelque chose, sinon nil.
    func approvalNeeded(name: String, input: JSONValue) -> ApprovalRequest? {
        switch name {
        case "create_event":
            return ApprovalRequest(title: "Créer un événement",
                                   details: [input["title"]?.string,
                                             Self.display(input["start"]?.string).map { "Début : \($0)" },
                                             Self.display(input["end"]?.string).map { "Fin : \($0)" },
                                             input["location"]?.string.map { "Lieu : \($0)" }]
                                       .compactMap { $0 }.joined(separator: "\n"))
        case "create_reminder":
            return ApprovalRequest(title: "Créer un rappel",
                                   details: [input["title"]?.string,
                                             Self.display(input["due"]?.string).map { "Échéance : \($0)" }]
                                       .compactMap { $0 }.joined(separator: "\n"))
        default:
            return nil
        }
    }

    // MARK: - Exécution

    func run(name: String, input: JSONValue) async -> ToolOutput {
        do {
            switch name {
            case "list_events": return try await listEvents(input)
            case "create_event": return try await createEvent(input)
            case "list_reminders": return try await listReminders()
            case "create_reminder": return try await createReminder(input)
            case "compose_email": return await composeEmail(input)
            case "search_contacts": return try await searchContacts(input)
            case "search_places": return try await searchPlaces(input)
            case "open_directions": return openDirections(input)
            case "call_phone": return callPhone(input)
            case "open_muse": return openMuse(input)
            default: return ToolOutput(text: "Outil inconnu : \(name)", isError: true)
            }
        } catch {
            return ToolOutput(text: "Erreur : \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: Agenda

    private func calendarAccess() async throws {
        guard try await eventStore.requestFullAccessToEvents() else {
            throw ClaudeError(message: "Accès à l'agenda refusé (Réglages iOS > Confidentialité > Calendriers).")
        }
    }

    private func listEvents(_ input: JSONValue) async throws -> ToolOutput {
        try await calendarAccess()
        guard let start = Self.parseDate(input["start"]?.string),
              let end = Self.parseDate(input["end"]?.string) else {
            return ToolOutput(text: "Dates invalides.", isError: true)
        }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate).prefix(100)
        if events.isEmpty { return ToolOutput(text: "Aucun événement sur cette période.") }
        let list: [JSONValue] = events.map { e in
            ["title": .string(e.title ?? ""),
             "start": .string(Self.iso(e.startDate)), "end": .string(Self.iso(e.endDate)),
             "all_day": .bool(e.isAllDay), "location": .string(e.location ?? ""),
             "calendar": .string(e.calendar?.title ?? "")]
        }
        return ToolOutput(text: JSONValue.array(list).jsonString)
    }

    private func createEvent(_ input: JSONValue) async throws -> ToolOutput {
        try await calendarAccess()
        guard let title = input["title"]?.string,
              let start = Self.parseDate(input["start"]?.string),
              let end = Self.parseDate(input["end"]?.string) else {
            return ToolOutput(text: "Titre ou dates invalides.", isError: true)
        }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = input["location"]?.string
        event.notes = input["notes"]?.string
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        return ToolOutput(text: "Événement créé : \(title), \(Self.iso(start)) → \(Self.iso(end)).")
    }

    // MARK: Rappels

    private func remindersAccess() async throws {
        guard try await eventStore.requestFullAccessToReminders() else {
            throw ClaudeError(message: "Accès aux rappels refusé (Réglages iOS > Confidentialité > Rappels).")
        }
    }

    private func listReminders() async throws -> ToolOutput {
        try await remindersAccess()
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        if reminders.isEmpty { return ToolOutput(text: "Aucun rappel en cours.") }
        let list: [JSONValue] = reminders.prefix(100).map { r in
            let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            return ["title": .string(r.title ?? ""), "due": due.map { .string(Self.iso($0)) } ?? .null,
                    "list": .string(r.calendar?.title ?? "")]
        }
        return ToolOutput(text: JSONValue.array(list).jsonString)
    }

    private func createReminder(_ input: JSONValue) async throws -> ToolOutput {
        try await remindersAccess()
        guard let title = input["title"]?.string else {
            return ToolOutput(text: "Intitulé manquant.", isError: true)
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = input["notes"]?.string
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if let due = Self.parseDate(input["due"]?.string) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try eventStore.save(reminder, commit: true)
        return ToolOutput(text: "Rappel créé : \(title).")
    }

    // MARK: E-mail

    private func composeEmail(_ input: JSONValue) async -> ToolOutput {
        let to = input["to"]?.array?.compactMap(\.string) ?? []
        let subject = input["subject"]?.string ?? ""
        let body = input["body"]?.string ?? ""

        guard MFMailComposeViewController.canSendMail(), let presenter = UIApplication.topViewController() else {
            // Pas de compte Mail configuré : on passe par un lien mailto: (Gmail, Outlook…)
            var c = URLComponents()
            c.scheme = "mailto"
            c.path = to.joined(separator: ",")
            c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
            if let url = c.url { _ = await UIApplication.shared.open(url) }
            return ToolOutput(text: "Brouillon ouvert dans l'app de messagerie par défaut. L'utilisateur l'enverra lui-même.")
        }

        return await withCheckedContinuation { cont in
            let delegate = MailDelegate { result in
                switch result {
                case .sent: cont.resume(returning: ToolOutput(text: "E-mail envoyé par l'utilisateur."))
                case .saved: cont.resume(returning: ToolOutput(text: "L'utilisateur a enregistré le brouillon sans l'envoyer."))
                case .failed: cont.resume(returning: ToolOutput(text: "L'envoi a échoué.", isError: true))
                default: cont.resume(returning: ToolOutput(text: "L'utilisateur a annulé l'envoi."))
                }
            }
            mailDelegate = delegate
            let vc = MFMailComposeViewController()
            vc.mailComposeDelegate = delegate
            vc.setToRecipients(to)
            vc.setSubject(subject)
            vc.setMessageBody(body, isHTML: false)
            presenter.present(vc, animated: true)
        }
    }

    // MARK: Contacts

    private func searchContacts(_ input: JSONValue) async throws -> ToolOutput {
        guard try await contactStore.requestAccess(for: .contacts) else {
            return ToolOutput(text: "Accès aux contacts refusé (Réglages iOS > Confidentialité > Contacts).", isError: true)
        }
        let query = input["query"]?.string ?? ""
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                                       CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let contacts = try contactStore.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)
        if contacts.isEmpty { return ToolOutput(text: "Aucun contact trouvé pour « \(query) ».") }
        let list: [JSONValue] = contacts.prefix(20).map { c in
            ["name": .string("\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)),
             "organization": .string(c.organizationName),
             "phones": .array(c.phoneNumbers.map { .string($0.value.stringValue) }),
             "emails": .array(c.emailAddresses.map { .string($0.value as String) })]
        }
        return ToolOutput(text: JSONValue.array(list).jsonString)
    }

    // MARK: Lieux

    private func searchPlaces(_ input: JSONValue) async throws -> ToolOutput {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = input["query"]?.string ?? ""
        let response = try await MKLocalSearch(request: request).start()
        if response.mapItems.isEmpty { return ToolOutput(text: "Aucun lieu trouvé.") }
        let list: [JSONValue] = response.mapItems.prefix(8).map { item in
            ["name": .string(item.name ?? ""),
             "address": .string(item.placemark.title ?? ""),
             "phone": .string(item.phoneNumber ?? ""),
             "website": .string(item.url?.absoluteString ?? "")]
        }
        return ToolOutput(text: JSONValue.array(list).jsonString)
    }

    private func openDirections(_ input: JSONValue) -> ToolOutput {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "daddr", value: input["destination"]?.string ?? "")]
        guard let url = c.url else { return ToolOutput(text: "Destination invalide.", isError: true) }
        UIApplication.shared.open(url)
        return ToolOutput(text: "Itinéraire ouvert dans Plans.")
    }

    private func callPhone(_ input: JSONValue) -> ToolOutput {
        let digits = (input["number"]?.string ?? "").filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else {
            return ToolOutput(text: "Numéro invalide.", isError: true)
        }
        UIApplication.shared.open(url)
        return ToolOutput(text: "Appel proposé à l'utilisateur pour le \(digits).")
    }

    // MARK: muse.ai

    private func openMuse(_ input: JSONValue) -> ToolOutput {
        var target: URL? = nil
        if let s = input["url"]?.string, let url = URL(string: s), url.scheme == "https",
           let host = url.host, host == "muse.ai" || host.hasSuffix(".muse.ai") {
            target = url
        }
        AppState.shared.openMuse(target)
        return ToolOutput(text: "Onglet muse.ai affiché" + (target.map { " sur \($0.absoluteString)." } ?? "."))
    }

    // MARK: - Dates

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f.string(from: date)
    }

    static func display(_ s: String?) -> String? {
        guard let d = parseDate(s) else { return nil }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()
            .locale(Locale(identifier: "fr_FR")))
    }
}

private final class MailDelegate: NSObject, MFMailComposeViewControllerDelegate {
    let completion: (MFMailComposeResult) -> Void
    init(completion: @escaping (MFMailComposeResult) -> Void) { self.completion = completion }

    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
        completion(result)
    }
}

extension UIApplication {
    @MainActor static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
