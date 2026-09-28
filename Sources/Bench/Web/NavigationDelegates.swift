// NavigationDelegates.swift — the two navigation policies (DESIGN.md, Web
// routing policy). The main web view stays on the daemon and sends everything
// else away; every other web view allows navigation inside itself.
import AppKit
import WebKit

/// The one main web view's policy.
@MainActor
final class MainNavigationDelegate: NSObject, WKNavigationDelegate {
    /// Set once by the container right after it is built.
    weak var container: WebContainer?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let policy = Downloads.policy(for: navigationAction) { return policy }

        // Iframes stay where they are. A nil target frame is a new window,
        // which `createWebViewWith` routes; deciding here as well would open
        // an external link twice.
        guard let frame = navigationAction.targetFrame, frame.isMainFrame else { return .allow }

        let url = navigationAction.request.url
        let target = WebRoute.classify(url, daemonPort: container?.port)
        switch target {
        case .daemon, .inert:
            return .allow
        case .preview, .web, .external:
            if let url { LinkDispatcher.open(url, as: target) }
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        // The daemon refuses a browser it doesn't know: sign in again, on
        // the page that was asked for.
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse, http.statusCode == 401,
           let url = http.url, WebRoute.classify(url, daemonPort: container?.port) == .daemon,
           container?.signInRejected(at: url) == true {
            return .cancel
        }
        return Downloads.policy(for: navigationResponse) ?? .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        container?.mainFrameFinished(at: webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        container?.mainFrameFailed(with: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        container?.mainFrameFailed(with: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        container?.contentProcessTerminated()
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        Downloads.adopt(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        Downloads.adopt(download)
    }
}

/// The policy of every other web view: pop-ups, and the Browser and Preview
/// windows. Pages there may go anywhere (OAuth to other sites happens in
/// them), so it only sends downloads and non-web schemes to their handlers.
///
/// One thing differs. A pop-up may load the daemon's pages, because the
/// pop-out pool and connector sign-ins depend on it. A Browser or Preview
/// window may not: Claude Science lives in the one main web view, so a link
/// to it from there goes to that view rather than opening a second copy.
@MainActor
final class EmbeddedNavigationDelegate: NSObject, WKNavigationDelegate {
    /// WebKit keeps its navigation delegate weak, so these are long-lived
    /// objects shared by every such web view.
    static let popups = EmbeddedNavigationDelegate(sendsDaemonPagesToMainView: false)
    static let linkWindows = EmbeddedNavigationDelegate(sendsDaemonPagesToMainView: true)

    private let sendsDaemonPagesToMainView: Bool

    private init(sendsDaemonPagesToMainView: Bool) {
        self.sendsDaemonPagesToMainView = sendsDaemonPagesToMainView
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let policy = Downloads.policy(for: navigationAction) { return policy }
        guard navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url else { return .allow }

        let target = WebRoute.classify(url, daemonPort: WebContainer.shared.port)
        switch target {
        case .external:
            LinkDispatcher.openExternally(url)
            return .cancel
        case .daemon where sendsDaemonPagesToMainView:
            LinkDispatcher.open(url, as: .daemon)
            return .cancel
        default:
            return .allow
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        Downloads.policy(for: navigationResponse) ?? .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        Downloads.adopt(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        Downloads.adopt(download)
    }
}
