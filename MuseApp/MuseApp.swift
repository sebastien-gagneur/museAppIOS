import SwiftUI

@main
struct MuseApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        // Les trois écrans restent en mémoire : on garde la conversation et la page muse.ai.
        ZStack {
            screen(.agent) { ChatView() }
            screen(.muse) { MuseTab(model: appState.web) }
            screen(.settings) { SettingsView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(web: appState.web)
        }
    }

    private func screen<V: View>(_ tab: AppState.Tab, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .opacity(appState.tab == tab ? 1 : 0)
            .allowsHitTesting(appState.tab == tab)
            .accessibilityHidden(appState.tab != tab)
    }
}

/// Barre du bas : Agent, Retour, muse.ai, Avancer, Réglages.
struct BottomBar: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var web: WebViewModel

    var body: some View {
        HStack(spacing: 0) {
            item("Agent", selected: appState.tab == .agent) {
                Image(systemName: "sparkles")
            } action: { appState.tab = .agent }

            item("Retour", enabled: web.canGoBack) {
                Image(systemName: "chevron.backward")
            } action: { appState.goBack() }

            item("muse.ai", selected: appState.tab == .muse) {
                Image("MuseTabIcon").renderingMode(.template)
                    .resizable().scaledToFit().frame(height: 20)
            } action: { appState.tapMuse() }
            .contextMenu {
                Button { appState.goHome() } label: { Label("Accueil muse.ai", systemImage: "house") }
                Button { web.reload() } label: { Label("Recharger", systemImage: "arrow.clockwise") }
            }

            item("Avancer", enabled: web.canGoForward) {
                Image(systemName: "chevron.forward")
            } action: { appState.goForward() }

            item("Réglages", selected: appState.tab == .settings) {
                Image(systemName: "gearshape")
            } action: { appState.tab = .settings }
        }
        .padding(.top, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func item<Icon: View>(_ title: String, selected: Bool = false, enabled: Bool = true,
                                  @ViewBuilder icon: () -> Icon,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon().font(.system(size: 20, weight: .medium)).frame(height: 24)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
