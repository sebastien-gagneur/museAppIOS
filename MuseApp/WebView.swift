import SwiftUI
import WebKit

final class WebViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var showError = false
    @Published var errorMessage = ""
    weak var webView: WKWebView?

    func reload() { webView?.reload() }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebViewModel
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Stockage persistant : tu restes connecté entre deux lancements.
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true   // swipe retour/avant
        if #available(iOS 16.4, *) { webView.isInspectable = true }

        // Tirer vers le bas pour rafraîchir
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        context.coordinator.observe(webView)
        model.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: WebViewModel
        private var progressObs: NSKeyValueObservation?

        init(model: WebViewModel) { self.model = model }

        func observe(_ webView: WKWebView) {
            progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.model.progress = wv.estimatedProgress }
            }
        }

        @objc func pullToRefresh(_ sender: UIRefreshControl) {
            model.webView?.reload()
            sender.endRefreshing()
        }

        // Liens non web (mailto:, tel:, itms-apps:…) -> ouverts hors de l'app
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
                return decisionHandler(.allow)
            }
            if ["http", "https", "about", "blob", "data"].contains(scheme) {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        // Liens target="_blank" / window.open -> ouverts dans la même vue
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // Boîtes de dialogue JavaScript (alert / confirm)
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert, from: webView) ?? completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(alert, from: webView) ?? completionHandler(false)
        }

        private func present(_ vc: UIViewController, from view: UIView) -> Void? {
            guard let root = view.window?.rootViewController else { return nil }
            var top = root
            while let p = top.presentedViewController { top = p }
            top.present(vc, animated: true)
            return ()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let e = error as NSError
            guard e.code != NSURLErrorCancelled else { return }
            model.errorMessage = e.localizedDescription
            model.showError = true
        }
    }
}
