import Cocoa
import QuickLookUI
import WebKit

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!

    /// Quick Look's completion handler, held until the WebView has actually painted.
    /// Wrapped so it is called exactly once, whichever of the three paths gets there
    /// first: load finished, load failed, or the watchdog fired.
    private var pendingHandler: ((Error?) -> Void)?

    /// Upper bound on how long we make Quick Look wait for a render.
    private static let renderTimeout: TimeInterval = 5

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        // Nothing in a preview should ever run a plugin, open a window, or navigate.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // The Quick Look panel isn't a browser: no rubber-banding, no back/forward.
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        self.webView = webView
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        pendingHandler = handler

        // Reading the file and base64-inlining its images is unbounded work; doing it
        // on the main thread stalls the Quick Look panel until it finishes.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try MarkdownRenderer.renderHTML(forFileAt: url) }

            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let html):
                    self.webView.loadHTMLString(html, baseURL: nil)
                    // Don't report readiness yet — wait for didFinish, so Quick Look
                    // never displays or snapshots the placeholder instead of the file.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.renderTimeout) { [weak self] in
                        self?.finish(with: nil)
                    }
                case .failure(let error):
                    self.finish(with: error)
                }
            }
        }
    }

    private func finish(with error: Error?) {
        guard let handler = pendingHandler else { return }
        pendingHandler = nil
        handler(error)
    }
}

extension PreviewViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // The only navigation we ever perform is our own loadHTMLString.
        guard navigationAction.navigationType != .other else {
            decisionHandler(.allow)
            return
        }

        // A link click would otherwise replace the preview with a web page *inside*
        // the Quick Look panel, with no way back. Hand it to the browser instead.
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: error)
    }
}

extension PreviewViewController: WKUIDelegate {

    /// Never let previewed content spawn a window, alert, prompt or confirm panel.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
}
