import SwiftUI

/// Page d'accueil de muse.ai.
let museStartURL = URL(string: "https://muse.ai")!

struct MuseTab: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        ZStack(alignment: .top) {
            WebView(model: model, url: museStartURL)
            if model.progress < 1 {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
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
