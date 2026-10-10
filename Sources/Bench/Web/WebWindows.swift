// WebWindows.swift — the extra windows a page can open (DESIGN.md, Web
// routing policy): real child pop-ups, and the Browser and Preview windows.
// This is the one owner that keeps them alive until they close.
import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
final class WebWindows {
    static let shared = WebWindows()
    private init() {}

    private var popups: [PopupWindow] = []
    private var browsers: [BrowserWindow] = []
    private var cascadePoint = NSPoint.zero

    /// A real child web view from the configuration WebKit passed, so the
    /// page keeps `window.opener` and `postMessage`. It must be returned to
    /// WebKit, which then loads whatever the page asked for.
    func openPopup(configuration: WKWebViewConfiguration, features: WKWindowFeatures) -> WKWebView {
        let popup = PopupWindow(configuration: configuration, features: features)
        popups.append(popup)
        show(popup.window)
        return popup.webView
    }

    /// A link to somewhere else on the web.
    func openBrowser(_ url: URL) {
        open(BrowserWindow(kind: .browser, url: url))
    }

    /// A generated HTML preview from the daemon's other port.
    func openPreview(_ url: URL) {
        open(BrowserWindow(kind: .preview, url: url))
    }

    private func open(_ browser: BrowserWindow) {
        browsers.append(browser)
        show(browser.window)
    }

    /// Called from a window's `windowWillClose`. Removal waits a turn, so the
    /// object isn't released in the middle of its own delegate callback.
    func forget(_ object: AnyObject) {
        Task { @MainActor in
            popups.removeAll { $0 === object }
            browsers.removeAll { $0 === object }
        }
    }

    private func show(_ window: NSWindow) {
        window.center()
        cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// A child window whose web view a page opened with `window.open`.
@MainActor
private final class PopupWindow: NSObject, NSWindowDelegate, WebPageWindow {
    let webView: WKWebView
    let finder: PageFinder
    let window: NSWindow
    private let uiDelegate = WebUIDelegate(role: .popup)
    private var titleObserver: AnyCancellable?

    init(configuration: WKWebViewConfiguration, features: WKWindowFeatures) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        WebSetup.finish(webView)
        finder = PageFinder(webView: webView)

        let width = features.width.map { CGFloat($0.doubleValue) } ?? 900
        let height = features.height.map { CGFloat($0.doubleValue) } ?? 700
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(width, 320), height: max(height, 240)),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        // SwiftUI hosts the web view so the find bar can sit over it, as in
        // the Browser window. The window's size is ours, not the view's.
        let hosting = NSHostingView(rootView: PopupWindowView(webView: webView, finder: finder))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self

        webView.navigationDelegate = EmbeddedNavigationDelegate.popups
        webView.uiDelegate = uiDelegate
        uiDelegate.onClose = { [weak self] in self?.window.close() }
        titleObserver = webView.publisher(for: \.title).sink { [weak window] title in
            window?.title = title ?? ""
        }
    }

    func windowWillClose(_ notification: Notification) {
        titleObserver = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        WebWindows.shared.forget(self)
    }
}

/// A pop-up's content: its web view, and the find bar when shown.
private struct PopupWindowView: View {
    let webView: WKWebView
    let finder: PageFinder

    var body: some View {
        WebViewHost(webView: webView)
            .overlay(alignment: .top) {
                FindOverlay(finder: finder)
            }
    }
}
