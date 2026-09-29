// WebContainer.swift — the one web view on the Claude Science daemon
// (DESIGN.md, Daemon and sign-in). It is made once and never recreated, so
// Claude Science keeps its one document. The daemon, the routing, the windows
// and the notification bridge live in the files beside this one; this owns the
// web view and what the App's toolbar, menus and Router ask of it.
import Combine
import os
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
    /// The session the page is showing (`/projects/<p>/frames/<id>`), or nil
    /// anywhere else: what the context ring is about.
    @Published private(set) var currentFrameID: String?
    @Published var isFindVisible = false
    /// Bumped on every ⌘F, so a find bar that is already open takes focus again.
    @Published private(set) var findRequest = 0

    /// The one web view on the daemon. Created once, never recreated.
    let webView: WKWebView
    /// The daemon's port, once known.
    private(set) var port: Int?

    // WebKit holds its delegates weakly, so they live here.
    private let navigationDelegate = MainNavigationDelegate()
    private let uiDelegate = WebUIDelegate(role: .main)
    private let notifications: NotificationBridge

    /// The start in progress, if any.
    private var startTask: Task<Void, Never>?
    /// A URL asked for before the daemon's port was known (a `bench://` link
    /// that launched the app). It becomes the sign-in's destination.
    private var pendingURL: URL?
    private var lastSignInRetry: ContinuousClock.Instant?
    private var lastSessionRecovery: ContinuousClock.Instant?

    private static let zoomRange = 0.5...3.0
    private static let zoomStep = 0.1
    private static let signInRetryInterval = Duration.seconds(30)

    private init() {
        // A web view copies its configuration when it is made, so all of it is
        // set first.
        let configuration = WebSetup.makeConfiguration()
        let bridge = NotificationBridge(daemonPort: { WebContainer.shared.port })
        bridge.install(on: configuration.userContentController)
        notifications = bridge

        webView = WKWebView(frame: .zero, configuration: configuration)
        WebSetup.finish(webView)

        navigationDelegate.container = self
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = uiDelegate
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        webView.publisher(for: \.url)
            .map { Self.frameID(in: $0) }
            .removeDuplicates()
            .assign(to: &$currentFrameID)
        webView.pageZoom = Self.storedZoom()
    }

    // MARK: Starting

    /// Starts the daemon if needed, signs in, and registers Router.navigate
    /// and Router.clickWebNotification. Also the "Try again" button.
    ///
    /// Only one start runs at a time. A second one would ask `status` while
    /// the first one's daemon is still booting, hear "not running", and run
    /// `serve` again on top of it.
    func start() {
        Router.shared.navigate = { [weak self] url in self?.load(url) }
        Router.shared.clickWebNotification = { [weak self] id in
            guard let self else { return }
            notifications.click(id, in: webView)
        }

        guard startTask == nil else { return }
        status = .starting
        lastSignInRetry = nil
        startTask = Task {
            defer { startTask = nil }
            do {
                let daemon = try await DaemonController.ensureRunning()
                await signIn(port: daemon.port)
            } catch {
                let sentence = (error as? DaemonError)?.sentence ?? "Couldn't reach Claude Science. Try again."
                Logger.web.error("Start failed: \(sentence, privacy: .public)")
                status = .failed(sentence)
            }
        }
    }

    /// Loads the daemon's page with a fresh sign-in code. Without one (the CLI
    /// gave none) it loads the page anyway: the cookie from last time may
    /// still work, and if not, the 401 asks for a code again.
    private func signIn(port: Int) async {
        self.port = port
        guard let root = URL(string: "http://localhost:\(port)/") else {
            status = .failed("Couldn't build Claude Science's address.")
            return
        }
        let requested = pendingURL.map(Self.canonical)
        pendingURL = nil
        let destination = requested.flatMap { WebRoute.classify($0, daemonPort: port) == .daemon ? $0 : nil } ?? root

        let nonce = await DaemonController.freshNonce()
        webView.load(URLRequest(url: nonce.map { addingLoginNonce($0, to: destination) } ?? destination))
    }

    // MARK: Navigation

    /// Loads a daemon URL in the one web view. The navigation delegate still
    /// routes it, so a URL that isn't the daemon's ends up in a Browser window.
    func load(_ url: URL) {
        guard port != nil else {
            pendingURL = url
            return
        }
        webView.load(URLRequest(url: Self.canonical(url)))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    /// Only a failure restarts. While the daemon is starting, Reload must not
    /// start it again, and with nothing loaded yet it has nothing to reload.
    func reload() {
        if case .failed = status {
            start()
        } else if webView.url != nil {
            webView.reload()
        }
    }

    /// The daemon answers 401 to a browser it doesn't know. Get a new code and
    /// load the same page with it, once per 30 s. Returns whether the 401 is
    /// being handled, so the navigation should be dropped.
    ///
    /// A second refusal inside that time means signing in isn't working, and
    /// looping wouldn't help. While starting that is a failure. Once Claude
    /// Science is up it is just a page the daemon won't give us, so the 401
    /// shows as it is instead of covering a working app.
    func signInRejected(at url: URL) -> Bool {
        let now = ContinuousClock.now
        if let last = lastSignInRetry, now - last < Self.signInRetryInterval {
            Logger.web.error("The daemon refused the sign-in again")
            guard status == .starting else { return false }
            status = .failed("Claude Science didn't accept the sign-in. Try again.")
            return true
        }
        lastSignInRetry = now
        Task {
            guard let nonce = await DaemonController.freshNonce() else {
                status = .failed("Couldn't get a sign-in code from Claude Science. Try again.")
                return
            }
            webView.load(URLRequest(url: addingLoginNonce(nonce, to: url)))
        }
        return true
    }

    /// An API read from the page came back 401: the page is showing Claude
    /// Science's "Sign in" card, because its session didn't take (seen now
    /// and then right after a restart). Sign in again with a fresh code, on
    /// the page that is showing, as a 401 page does. At most once in ten
    /// minutes: if Claude Science's own account needs signing in, a new code
    /// can't fix that, and reloading would get in the way of its Sign in.
    func sessionLost() {
        let now = ContinuousClock.now
        if let last = lastSessionRecovery, now - last < .seconds(600) { return }
        guard let url = webView.url, WebRoute.classify(url, daemonPort: port) == .daemon else { return }
        lastSessionRecovery = now
        Logger.web.info("An API read was refused; signing in again")
        Task {
            guard let nonce = await DaemonController.freshNonce() else { return }
            webView.load(URLRequest(url: addingLoginNonce(nonce, to: Self.canonical(url))))
        }
    }

    /// The first daemon page to finish loading means we are in.
    func mainFrameFinished(at url: URL?) {
        guard WebRoute.classify(url, daemonPort: port) == .daemon else { return }
        status = .ready
    }

    /// A page that can't be loaded from the daemon. Cancelled loads are our own
    /// doing (a routed link, a 401 that gets a new code, a download turned
    /// into a file) and are not failures. Anything else while starting is one,
    /// or the spinner would never end; once Claude Science is up, only network
    /// errors are, and other errors leave the page as it is.
    func mainFrameFailed(with error: Error) {
        let failure = error as NSError
        let isNetworkError = failure.domain == NSURLErrorDomain
        if isNetworkError, failure.code == NSURLErrorCancelled { return }
        // "Frame load interrupted": what WebKit says for a policy cancel or a
        // response that became a download.
        if failure.domain == "WebKitErrorDomain", failure.code == 102 { return }
        guard isNetworkError || status == .starting else { return }
        let failedURL = failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        guard failedURL == nil || WebRoute.classify(failedURL, daemonPort: port) == .daemon else { return }

        Logger.web.error("Main frame failed: \(failure.localizedDescription, privacy: .public)")
        let unreachable = [NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut, NSURLErrorCannotFindHost]
        if isNetworkError, unreachable.contains(failure.code), let port {
            status = .failed("Claude Science isn't responding on port \(port).")
        } else {
            status = .failed("Couldn't open Claude Science: \(failure.localizedDescription)")
        }
    }

    /// WebKit ended the page's process (memory, or a crash). A reload starts a
    /// new one.
    func contentProcessTerminated() {
        Logger.web.error("The web content process ended; reloading")
        reload()
    }

    /// Cookies are kept per host, so 127.0.0.1 and localhost would be two
    /// sign-ins. Everything Bench loads uses localhost.
    private static func canonical(_ url: URL) -> URL {
        guard url.host == "127.0.0.1", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.host = "localhost"
        return parts.url ?? url
    }

    // MARK: Zoom

    func zoomIn() { setZoom(Double(webView.pageZoom) + Self.zoomStep) }
    func zoomOut() { setZoom(Double(webView.pageZoom) - Self.zoomStep) }
    func resetZoom() { setZoom(1.0) }

    /// Steps are rounded to a tenth so repeated ±0.1 doesn't drift.
    private func setZoom(_ value: Double) {
        let zoom = min(max((value * 10).rounded() / 10, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        webView.pageZoom = zoom
        UserDefaults.standard.set(zoom, forKey: SettingsKey.pageZoom)
    }

    private static func storedZoom() -> Double {
        let stored = UserDefaults.standard.object(forKey: SettingsKey.pageZoom) as? Double ?? 1.0
        return min(max(stored, zoomRange.lowerBound), zoomRange.upperBound)
    }

    // MARK: Find

    func showFind() {
        isFindVisible = true
        findRequest += 1
    }
}
