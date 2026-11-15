import SwiftUI
import WebKit

struct SettingsView: View {
    @State private var apiKey = Keychain.apiKey ?? ""
    @State private var saved = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Enregistrer") {
                        Keychain.apiKey = apiKey
                        saved = true
                    }
                    Link("Obtenir une clé sur console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                } header: {
                    Text("Clé API Anthropic")
                } footer: {
                    Text(saved ? "Clé enregistrée dans le trousseau de l'iPhone."
                               : "L'agent utilise Claude (\(ClaudeClient.model)). Chaque demande est facturée sur ton compte Anthropic.")
                }

                Section("muse.ai") {
                    Button("Se déconnecter de muse.ai", role: .destructive) { confirmLogout = true }
                }

                Section("Autorisations") {
                    Button("Ouvrir les réglages iOS de l'app") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .navigationTitle("Réglages")
            .confirmationDialog("Effacer la session muse.ai ?", isPresented: $confirmLogout) {
                Button("Se déconnecter", role: .destructive) {
                    let store = WKWebsiteDataStore.default()
                    store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                     modifiedSince: .distantPast) {
                        Task { @MainActor in AppState.shared.goHome() }
                    }
                }
            }
        }
    }
}
