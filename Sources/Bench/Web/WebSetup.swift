// WebSetup.swift — the settings every Bench web view shares (DESIGN.md, Web
// routing policy), so the main view, the Browser windows and the pop-ups all
// look like Safari to a page and behave alike.
import WebKit

enum WebSetup {
    /// A configuration for a web view Bench makes itself. Pop-ups don't use
    /// this: WebKit hands them a copy of their opener's.
    @MainActor
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // Cookies and localStorage persist, so the sign-in does too.
        configuration.websiteDataStore = .default()
        // A Safari-like user agent, since sites sniff for it.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        // As in Safari: pop-ups come from clicks, not from scripts on load.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
    }

    /// What is set on the web view itself, for ones we made and ones WebKit
    /// made for us.
    @MainActor
    static func finish(_ webView: WKWebView) {
        // An internal build, so the page can always be inspected.
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
    }
}
