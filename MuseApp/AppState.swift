import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Tab: Hashable { case agent, muse, settings }

    @Published var tab: Tab = .agent
    /// Navigateur de l'onglet muse.ai, partagé avec la barre du bas et l'agent.
    let web = WebViewModel()

    init() {
        // Pour les captures d'écran automatiques : `-startTab muse` ou `-startTab settings`.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count {
            switch args[i + 1] {
            case "muse": tab = .muse
            case "settings": tab = .settings
            default: break
            }
        }
    }

    /// Affiche l'onglet muse.ai, sur une page précise si demandée.
    func openMuse(_ url: URL?) {
        if let url { web.load(url) }
        tab = .muse
    }

    func goHome() {
        web.load(museStartURL)
        tab = .muse
    }

    func goBack() {
        tab = .muse
        web.goBack()
    }

    func goForward() {
        tab = .muse
        web.goForward()
    }

    /// Toucher l'onglet muse.ai alors qu'on y est déjà ramène à l'accueil de muse.ai.
    func tapMuse() {
        if tab == .muse { goHome() } else { tab = .muse }
    }
}
