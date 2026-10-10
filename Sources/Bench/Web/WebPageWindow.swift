// WebPageWindow.swift — which web page the View, Find and History menus act on
// (DESIGN.md, Main window). The main window, the Browser and Preview windows
// and the pop-ups each show one page, and a menu command goes to the page the
// user is looking at, not always to the main window's.
import AppKit
import Combine
import WebKit

/// A window that shows one web page, and what the menus can do to it. The
/// main window's page is `WebContainer`; the Browser, Preview and pop-up
/// windows are their own. The defaults are the plain page: zoom is per window
/// and not remembered, and Reload reloads.
@MainActor
protocol WebPageWindow: AnyObject {
    var webView: WKWebView { get }
    /// The window's find bar. Each window makes its own.
    var finder: PageFinder { get }

    func reload()
    func zoomIn()
    func zoomOut()
    func resetZoom()
    func goBack()
    func goForward()
    func showFind()
}

extension WebPageWindow {
    func reload() { webView.reload() }
    func zoomIn() { webView.pageZoom = PageZoom.zoomedIn(webView.pageZoom) }
    func zoomOut() { webView.pageZoom = PageZoom.zoomedOut(webView.pageZoom) }
    func resetZoom() { webView.pageZoom = PageZoom.actualSize }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func showFind() { finder.show() }
}

// MARK: Zoom

/// The zoom steps, shared by every window. The main window also remembers
/// where it ended up (WebContainer); the others start at actual size.
enum PageZoom {
    static let range = 0.5...3.0
    static let step = 0.1
    static let actualSize = 1.0

    static func zoomedIn(_ zoom: Double) -> Double { clamped(zoom + step) }
    static func zoomedOut(_ zoom: Double) -> Double { clamped(zoom - step) }

    /// Steps are rounded to a tenth so repeated ±0.1 doesn't drift.
    static func clamped(_ zoom: Double) -> Double {
        min(max((zoom * 10).rounded() / 10, range.lowerBound), range.upperBound)
    }
}

// MARK: Finding

/// One window's find bar: whether it shows, and the search itself over
/// WebKit's own find, so highlighting, scrolling and counting are the system's.
@MainActor
final class PageFinder: ObservableObject {
    @Published private(set) var isVisible = false
    /// Bumped on every ⌘F, so a find bar that is already open takes focus again.
    @Published private(set) var request = 0

    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func show() {
        isVisible = true
        request += 1
    }

    /// Finds `text`, wrapping around, and reports whether it is on the page.
    /// An empty string clears the highlight.
    func find(_ text: String, backwards: Bool) async -> Bool {
        guard let webView else { return false }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        configuration.caseSensitive = false
        let result = try? await webView.find(text, configuration: configuration)
        return result?.matchFound ?? false
    }

    /// Closes the bar and gives the keyboard back to the page.
    func close() {
        webView?.find("") { _ in }
        isVisible = false
        webView?.window?.makeFirstResponder(webView)
    }
}

// MARK: The page the menus act on

/// The page the user is looking at, and whether there is one. Commands ask
/// for `current` when they run, and watch `hasPage` to switch themselves off,
/// so a window with no page (Settings) leaves them dimmed.
///
/// The menus are SwiftUI's but the windows are AppKit's, with a web view as
/// the first responder, so there is nothing in SwiftUI's focus for a
/// `focusedSceneValue` to hang from. The key and main windows are what to ask.
@MainActor
final class ActiveWebPage: ObservableObject {
    static let shared = ActiveWebPage()

    @Published private(set) var hasPage = false
    private var observers: [AnyCancellable] = []

    private init() {
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
        ]
        // A turn later, when AppKit has settled on the new key window: during
        // the notification for the old one, `keyWindow` can still be empty.
        observers = names.map { name in
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        }
        refresh()
    }

    private func refresh() {
        let found = Self.current != nil
        if hasPage != found { hasPage = found }
    }

    /// The key window's page, else the main window's (see `choose`).
    static var current: (any WebPageWindow)? {
        choose(key: candidate(NSApp.keyWindow), main: candidate(NSApp.mainWindow))
    }

    private static func candidate(_ window: NSWindow?) -> Candidate<any WebPageWindow>? {
        guard let window else { return nil }
        return Candidate(page: page(in: window), isOverlay: window.sheetParent != nil || window is NSPanel)
    }

    /// The page in `window`: the window's delegate when it is one (the
    /// Browser, Preview and pop-up windows), or the one web view when it is
    /// the main window, which a different object manages.
    private static func page(in window: NSWindow) -> (any WebPageWindow)? {
        if let page = window.delegate as? any WebPageWindow { return page }
        return window.delegate is MainWindowController ? WebContainer.shared : nil
    }

    /// What `choose` needs to know about a window.
    struct Candidate<Page> {
        /// The window's page, if it has one.
        var page: Page?
        /// Whether it sits over another window: a sheet (Quick Open, an
        /// alert, an open panel) or a panel.
        var isOverlay: Bool
    }

    /// The key window's page if it has one. A key window without one is
    /// either an overlay, and the main window's page under it stays the
    /// target, or an ordinary window (Settings, Diagnostics), and there is no
    /// target at all. Without a key window, the main window's page.
    nonisolated static func choose<Page>(key: Candidate<Page>?, main: Candidate<Page>?) -> Page? {
        if let key {
            if let page = key.page { return page }
            if !key.isOverlay { return nil }
        }
        return main?.page
    }
}
