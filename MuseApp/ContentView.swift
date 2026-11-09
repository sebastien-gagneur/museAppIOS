import SwiftUI

/// Page chargée au démarrage. Change-la si ton dashboard est à une autre adresse.
let startURL = URL(string: "https://muse.ai/dashboard")!

struct ContentView: View {
    @StateObject private var model = WebViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            WebView(model: model, url: startURL)
                .ignoresSafeArea(edges: .bottom)

            if model.progress < 1 {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
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
