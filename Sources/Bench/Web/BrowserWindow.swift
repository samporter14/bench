// BrowserWindow.swift — the in-app window for links that leave Claude Science
// (DESIGN.md, Web routing policy): a plain web view with Back, Forward,
// Reload, the address, and, for web links, "Open in Safari". The Preview
// window is the same window with a fixed title and no Safari button. Find and
// zoom come from the menus, like the main window's (WebPageWindow).
import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
final class BrowserWindow: NSObject, NSWindowDelegate, ObservableObject, WebPageWindow {
    enum Kind {
        case browser
        case preview
    }

    let kind: Kind
    let webView: WKWebView
    let finder: PageFinder
    let window: NSWindow

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var address: URL?

    private let uiDelegate = WebUIDelegate(role: .contained)
    private var titleObserver: AnyCancellable?

    init(kind: Kind, url: URL) {
        self.kind = kind
        // Its own web view: a fresh configuration on the shared data store,
        // never the main view's, so nothing here can reach the daemon page.
        webView = WKWebView(frame: .zero, configuration: WebSetup.makeConfiguration())
        WebSetup.finish(webView)
        finder = PageFinder(webView: webView)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        let hosting = NSHostingController(rootView: BrowserWindowView(model: self))
        hosting.sceneBridgingOptions = [.toolbars]
        // The window's size is ours, not the web view's.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1100, height: 800))
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self

        webView.navigationDelegate = EmbeddedNavigationDelegate.linkWindows
        webView.uiDelegate = uiDelegate
        uiDelegate.onClose = { [weak self] in self?.window.close() }
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        webView.publisher(for: \.url).assign(to: &$address)

        switch kind {
        case .browser:
            titleObserver = webView.publisher(for: \.title).sink { [weak window] title in
                window?.title = title ?? ""
            }
        case .preview:
            window.title = "Preview"
        }
        webView.load(URLRequest(url: url))
    }

    func windowWillClose(_ notification: Notification) {
        titleObserver = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        // The window's view holds this model, and this holds the window: let go
        // of the view, or neither is ever freed.
        window.contentViewController = nil
        WebWindows.shared.forget(self)
    }

    /// The only road to Safari, and only on the user's click.
    fileprivate func openInSafari() {
        guard let address else { return }
        NSWorkspace.shared.open(address)
    }
}

private struct BrowserWindowView: View {
    @ObservedObject var model: BrowserWindow

    var body: some View {
        WebViewHost(webView: model.webView)
            .overlay(alignment: .top) {
                FindOverlay(finder: model.finder)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { model.webView.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                        .disabled(!model.canGoBack)
                        .help("Back")
                    Button { model.webView.goForward() } label: { Label("Forward", systemImage: "chevron.forward") }
                        .disabled(!model.canGoForward)
                        .help("Forward")
                    Button { model.webView.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        .help("Reload")
                }
                ToolbarItem(placement: .principal) {
                    Text(model.address?.absoluteString ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 200, idealWidth: 480, maxWidth: 640, alignment: .leading)
                }
                if model.kind == .browser {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.openInSafari() } label: { Label("Open in Safari", systemImage: "safari") }
                            .disabled(model.address == nil)
                            .help("Open in Safari")
                    }
                }
            }
    }
}
