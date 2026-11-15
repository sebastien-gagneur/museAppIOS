import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Tab: Hashable { case agent, muse, settings }

    @Published var tab: Tab = .agent
    /// Navigateur de l'onglet muse.ai, partagé avec la barre du bas et l'agent.
    let web = WebViewModel()

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
