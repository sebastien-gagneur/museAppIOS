import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Tab: Hashable { case agent, muse, settings }

    @Published var tab: Tab = .agent
    /// Page muse.ai à afficher (demandée par l'agent ou par les réglages).
    @Published var museRequest: (url: URL, id: UUID)?

    func openMuse(_ url: URL?) {
        museRequest = (url ?? museStartURL, UUID())
        tab = .muse
    }
}
