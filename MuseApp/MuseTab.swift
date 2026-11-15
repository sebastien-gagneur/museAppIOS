import SwiftUI

/// Page muse.ai chargée au démarrage de l'onglet. Change-la si besoin.
let museStartURL = URL(string: "https://muse.ai")!

struct MuseTab: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = WebViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            WebView(model: model, url: museStartURL)
            if model.progress < 1 {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
            }
        }
        .onAppear { if let r = appState.museRequest { model.load(r.url) } }
        .onChange(of: appState.museRequest?.id) { _, _ in
            if let r = appState.museRequest { model.load(r.url) }
        }
        .alert("Impossible de charger la page",
               isPresented: $model.showError,
               actions: {
                   Button("Réessayer") { model.reload() }
                   Button("OK", role: .cancel) {}
               },
               message: { Text(model.errorMessage) })
    }
}
