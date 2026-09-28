// WebContainer.swift — STUB, to be replaced by the web agent (DESIGN.md,
// "Daemon and sign-in", "Web routing policy", "Notification bridge").
// The public surface below is the contract the App and Router rely on; keep
// every name and signature.
import SwiftUI
import WebKit

@MainActor
final class WebContainer: ObservableObject {
    static let shared = WebContainer()

    enum Status: Equatable {
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var status: Status = .starting
    @Published var isFindVisible = false

    /// The one web view on the daemon. Created once, never recreated.
    let webView: WKWebView
    /// The daemon's port, once known.
    private(set) var port: Int?

    private init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    /// Starts the daemon if needed, signs in, and registers Router.navigate
    /// and Router.clickWebNotification.
    func start() {}
    func load(_ url: URL) {}
    func goBack() {}
    func goForward() {}
    func reload() {}
    func zoomIn() {}
    func zoomOut() {}
    func resetZoom() {}
    func showFind() { isFindVisible = true }
}

/// The window's content: the web view, the find bar when shown, and a quiet
/// state while starting or on failure.
struct BrowserView: View {
    var body: some View {
        Text("Web view goes here")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
