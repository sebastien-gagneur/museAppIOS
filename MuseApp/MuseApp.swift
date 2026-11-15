import SwiftUI

@main
struct MuseApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            TabView(selection: $appState.tab) {
                ChatView()
                    .tabItem { Label("Agent", systemImage: "sparkles") }
                    .tag(AppState.Tab.agent)
                MuseTab()
                    .tabItem { Label("muse.ai", systemImage: "globe") }
                    .tag(AppState.Tab.muse)
                SettingsView()
                    .tabItem { Label("Réglages", systemImage: "gearshape") }
                    .tag(AppState.Tab.settings)
            }
            .environmentObject(appState)
        }
    }
}
