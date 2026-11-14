// WebContainer.swift — the one web view on the Claude Science daemon
// (DESIGN.md, Daemon and sign-in). It lives as long as Capsid does, so Claude
// Science keeps its one document, unless "Keep Claude Science loaded when its
// window is closed" is off: then a closed window's page sleeps, the web view is
// let go so its process ends, and an identical one is made when the page is
// wanted again (Web/PageSleep.swift). The daemon, the routing, the windows and
// the notification bridge live in the files beside this one; this owns the web
// view and what the App's toolbar, menus and Router ask of it.
import Combine
import os
import SwiftUI
import WebKit

@MainActor
final class WebContainer: ObservableObject, WebPageWindow {
    static let shared = WebContainer()

    enum Status: Equatable {
        case starting
        case ready
        case failed(String)
        /// Unloaded on purpose while the main window is closed (Web/PageSleep.swift).
        /// Not a failure: nothing shows an error or retries, and every feature
        /// that waits for `.ready` is quietly off, as while starting.
        case asleep
    }

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var status: Status = .starting {
        didSet {
            // Close Other Tabs and Close All Tabs wait for a ready page.
            if status != oldValue { PageTabCommands.shared.refresh() }
            if status == .ready { retry.stop(resetting: true) }
            if case .failed = status {} else {
                retriesOnItsOwn = false
                companion = .none
            }
            if status != oldValue {
                if status != .starting, waking {
                    waking = false
                    // A link that came after the wake's sign-in chose its address.
                    if status == .ready, let url = pendingURL {
                        pendingURL = nil
                        load(url)
                    }
                }
                sleeper.pageChanged()
            }
        }
    }
    /// The failure on show is being retried on its own (Web/StartRetry.swift).
    @Published private(set) var retriesOnItsOwn = false
    /// How Capsid stands beside Claude Science's own app, when it does
    /// (Web/DaemonPolicy.swift). Only a failure carries one, so every feature
    /// that waits for `status == .ready` is already off while it is not
    /// `.none`; the window's overlay reads it to offer Open Claude Science.
    @Published private(set) var companion: Companion = .none {
        didSet {
            // While Capsid only reads, opening anything means opening Claude Science.
            if case .readOnly = companion {
                Router.shared.openInScience = { ScienceApp.open(.show) }
            } else {
                Router.shared.openInScience = nil
            }
        }
    }

    enum Companion: Equatable {
        case none
        /// Claude Science's app starts the daemon: Capsid waits for it.
        case waitingForApp
        /// Capsid can't sign in to the daemon: the database only.
        case readOnly(ReadOnlyReason)
    }
    /// The session the page is showing (`/projects/<p>/frames/<id>`), or nil
    /// anywhere else: what the context ring is about.
    @Published private(set) var currentFrameID: String?

    /// The one web view on the daemon. It is a `TabMenuWebView`, which adds the
    /// tab and Shelf items to its right-click menu. Made at launch and kept,
    /// except while the page sleeps (Web/PageSleep.swift): then it is let go, so
    /// its web content process ends, and `wake` makes an identical one. Read it
    /// when it is needed, never keep it: a kept one may be the page that slept.
    @Published private(set) var webView: WKWebView
    @Published private(set) var finder: PageFinder
    /// Closes the page's artifact tabs, one sweep at a time (Web/PageTabs.swift).
    private(set) lazy var tabCloser = PageTabCloser { [unowned self] request in await self.closeTabs(request) }
    /// The daemon's port, once known.
    private(set) var port: Int?
    /// The host its address uses (`daemon.url_host`), once known.
    private(set) var host = DaemonHost.usual
    /// The daemon the window signed in to, for the handover to compare with.
    private var signedInDaemon: CLIStatus?
    /// The card for "Capsid only reads" shows once a run.
    private var readOnlyAnnounced = false

    // WebKit holds its delegates weakly, so they live here.
    private let navigationDelegate = MainNavigationDelegate()
    private let uiDelegate = WebUIDelegate(role: .main)
    private let notifications: NotificationBridge
    private let handoverWatch: HandoverWatch
    /// Ask Another Model… in the page's model menu; the controller holds its handler weakly.
    private let modelMenu: ModelPickerMenu
    /// The right-click menu's tab items and Shelf items, given to each web view made.
    private let tabMenu: TabContextMenu
    private let shelfMenu: ConversationMenu
    /// The web view's address and back/forward watches; cancelled with the web
    /// view they watch, so nothing keeps a sleeping page alive.
    private var pageWatches: Set<AnyCancellable> = []

    /// The start in progress, if any.
    private var startTask: Task<Void, Never>?
    /// A URL asked for before the daemon's port was known (a `bench://` link
    /// that launched the app). It becomes the sign-in's destination.
    private var pendingURL: URL?
    private var lastSignInRetry: ContinuousClock.Instant?
    private var lastSessionRecovery: ContinuousClock.Instant?
    /// The sign-in is under way: a link that comes now waits in `pendingURL`
    /// for it to choose its destination, even though the port is known.
    private var signingIn = false
    /// Keeps the session on show for the next launch (Web/LastSession.swift).
    private let lastSession = LastSession()
    /// When the page last slept: its notifications from before are gone with it.
    private var lastSlept: Date?
    /// Where the page was when it went to sleep, to wake there.
    private var sleptAt: URL?
    /// A wake is under way: a link that comes now waits for the sign-in, which
    /// would otherwise replace it with where the page slept.
    @Published private(set) var waking = false
    /// When the page sleeps and wakes (Web/PageSleep.swift). With the setting
    /// on, the default, it never does either.
    private(set) lazy var sleeper = PageSleep(
        keepLoaded: PageSleepSetting.keepsLoaded(), windowOpen: true,
        page: { [unowned self] in
            switch status {
            case .ready: return signingIn || startTask != nil ? .busy : .loaded
            case .asleep: return .asleep
            case .starting, .failed: return .busy
            }
        },
        unload: { [unowned self] in sleep() },
        wake: { [unowned self] in wake() })

    private static let signInRetryInterval = Duration.seconds(30)
    /// Tries again, quietly, after a failure that may pass by itself.
    private lazy var retry = StartRetry(stillFailed: { [unowned self] in waitingToRetry },
                                        attach: { [unowned self] daemon in
                                            // A page that sleeps signs in when it wakes, not before.
                                            guard status != .asleep else { return }
                                            begin(found: daemon)
                                        })
    /// The page said Claude Science now opens in its own window (Web/HandoverWatch.swift).
    private lazy var handover: Handover = Handover(
        stopRetries: { [unowned self] in retry.stop(resetting: true) },
        post: { LabModel.shared.post($0) },
        watchForDaemon: { [unowned self] in newDaemonWatch.begin() })
    /// Asks `status` for the daemon the app starts, and signs in to it. Like
    /// `retry`, it only ever asks: it never starts one.
    private lazy var newDaemonWatch: StartRetry = StartRetry(
        probe: { [unowned self] in
            guard let now = await DaemonController.runningStatus() else { return nil }
            let old = await MainActor.run { signedInDaemon }
            return Handover.isNewDaemon(now, than: old) ? now : nil
        },
        // For about a quarter of an hour at most: a dialog with no new daemon behind it asks nothing more.
        stillFailed: { [unowned self] in
            handover.waitingForNewDaemon && newDaemonWatch.attempt < StartRetry.firstWaits.count + StartRetry.minuteTries
        },
        attach: { [unowned self] daemon in
            handover.waitingForNewDaemon = false
            guard status != .asleep else { return }
            begin(found: daemon)
        })

    private init() {
        let bridge = NotificationBridge(daemonPort: { WebContainer.shared.port })
        notifications = bridge
        // Hears the page's "now opens in its own window" dialog.
        let watch = HandoverWatch(daemonPort: { WebContainer.shared.port }, shown: { WebContainer.shared.handoverShown() })
        handoverWatch = watch
        // Which tab a right-click was on, for the menu's tab items (Web/TabContextMenu.swift).
        let tabMenu = TabContextMenu(daemonPort: { WebContainer.shared.port }, run: { request in
            Task { await WebContainer.shared.tabCloser.close(request) }
        })
        self.tabMenu = tabMenu
        // And which figure or file link, for Add to Shelf and its neighbours (Shelf/ConversationMenu.swift).
        let shelfMenu = ConversationMenu(
            daemonPort: { WebContainer.shared.port },
            isSession: { WebContainer.shared.currentFrameID.map(PlanCheck.isFrameID) == true },
            shelveSelection: { Task { await ConversationShelf.shared.shelveSelection() } },
            runDocument: { action, name in Task { await ConversationShelf.shared.run(action, named: name) } },
            run: { action, pick in Task { await ConversationShelf.shared.run(action, on: pick) } })
        self.shelfMenu = shelfMenu
        // And Ask Another Model… at the end of the page's model menu, with the message box's draft (AskModel/ModelPickerMenu.swift).
        let modelMenu = ModelPickerMenu(daemonPort: { WebContainer.shared.port }, mayOffer: { ModelPickerMenu.isWanted() },
                                        run: { draft in AskModelWindowController.shared.askFromModelMenu(draft: draft) })
        self.modelMenu = modelMenu

        let view = Self.makeWebView(notifications: bridge, handoverWatch: watch, tabMenu: tabMenu,
                                    shelfMenu: shelfMenu, modelMenu: modelMenu)
        webView = view
        finder = PageFinder(webView: view)
        self.watch(view)
    }

    /// A web view on the daemon, with everything the page needs from Capsid.
    /// The one at launch and every one a wake makes come from here, so they
    /// are the same. A web view copies its configuration when it is made, so
    /// all of it is set first.
    private static func makeWebView(notifications: NotificationBridge, handoverWatch: HandoverWatch, tabMenu: TabContextMenu,
                                    shelfMenu: ConversationMenu, modelMenu: ModelPickerMenu) -> WKWebView {
        let configuration = WebSetup.makeConfiguration()
        notifications.install(on: configuration.userContentController)
        handoverWatch.install(on: configuration.userContentController)
        tabMenu.install(on: configuration.userContentController)
        shelfMenu.install(on: configuration.userContentController)
        modelMenu.install(on: configuration.userContentController)

        let view = TabMenuWebView(frame: .zero, configuration: configuration)
        view.tabMenu = tabMenu
        tabMenu.webView = view
        view.shelfMenu = shelfMenu
        shelfMenu.webView = view
        modelMenu.webView = view
        WebSetup.finish(view)
        view.pageZoom = storedZoom()
        return view
    }

    /// Delegates and the watches on `view`'s back/forward and address.
    private func watch(_ view: WKWebView) {
        navigationDelegate.container = self
        view.navigationDelegate = navigationDelegate
        view.uiDelegate = uiDelegate
        pageWatches = []
        view.publisher(for: \.canGoBack).sink { [unowned self] in canGoBack = $0 }.store(in: &pageWatches)
        view.publisher(for: \.canGoForward).sink { [unowned self] in canGoForward = $0 }.store(in: &pageWatches)
        view.publisher(for: \.url)
            .map { Self.frameID(in: $0) }
            .removeDuplicates()
            .sink { [unowned self] in currentFrameID = $0 }
            .store(in: &pageWatches)
        // Where the user is, for "reopen where you were". Not `currentFrameID`:
        // it has the session but not its project.
        view.publisher(for: \.url).receive(on: DispatchQueue.main).sink { [weak self] url in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastSession.note(url: url, daemonPort: self.port)
                // And each project's last conversation, for Return to Project (Workspace/WorkspaceVisits.swift).
                WorkspaceCommands.shared.note(url: url, daemonPort: self.port)
            }
        }.store(in: &pageWatches)
    }

    // MARK: Starting

    /// Starts the daemon if needed, signs in, and registers Router.navigate
    /// and Router.clickWebNotification. Also the "Try again" button, which
    /// starts the automatic retries' waits over.
    func start() {
        Router.shared.navigate = { [weak self] url in self?.load(url) }
        Router.shared.pageForgot = { [weak self] notification in
            guard let slept = self?.lastSlept else { return false }
            return notification.receivedAt < slept
        }
        Router.shared.clickWebNotification = { [weak self] id in
            guard let self else { return }
            notifications.click(id, in: webView)
        }
        guard startTask == nil else { return }
        retry.stop(resetting: true)
        newDaemonWatch.stop(resetting: true)
        handover.waitingForNewDaemon = false
        begin(found: nil)
    }

    /// Only one start runs at a time. A second one would ask `status` while
    /// the first one's daemon is still booting, hear "not running", and run
    /// `serve` again on top of it. With `found`, the daemon has already
    /// answered (an automatic retry), so nothing is started, only signed in to.
    private func begin(found: CLIStatus?) {
        guard startTask == nil else { return }
        status = .starting
        lastSignInRetry = nil
        startTask = Task {
            defer {
                startTask = nil
                // A page that came up while this was finishing may sleep now.
                sleeper.pageChanged()
            }
            do {
                let daemon: CLIStatus
                if let found {
                    daemon = found
                } else {
                    daemon = try await DaemonController.ensureRunning(handoverSeen: handover.seen)
                }
                await signIn(daemon: daemon)
            } catch {
                let failure = error as? DaemonError
                let sentence = failure?.sentence ?? "Couldn't reach Claude Science. Try again."
                Logger.web.error("Start failed: \(sentence, privacy: .public)")
                fail(sentence, temporary: failure?.isTemporary ?? false,
                     companion: failure == .appOwnsServer ? .waitingForApp : .none)
            }
        }
    }

    /// Shows a failure. One that may pass by itself (Claude Science too busy
    /// to answer) is retried on its own until it answers (Web/StartRetry.swift);
    /// any other waits for Try again.
    private func fail(_ sentence: String, temporary: Bool, companion: Companion = .none) {
        // A wake that nothing on screen asked for (a phone request, a card's
        // action) and that couldn't sign in goes back to sleep: no failure to
        // show in a closed window, no tries in the background. The action that
        // wanted the page finds it not ready, as it would have before.
        if waking, !sleeper.wantsPageForItself {
            Logger.web.notice("The page couldn't wake: \(sentence, privacy: .public)")
            startTask?.cancel()
            backToSleep()
            return
        }
        status = .failed(sentence)
        retriesOnItsOwn = temporary
        self.companion = companion
        if temporary {
            retry.begin()
        } else {
            retry.stop(resetting: false)
        }
    }

    /// The window still shows a failure, and no start is under way.
    private var waitingToRetry: Bool {
        guard case .failed = status else { return false }
        return startTask == nil
    }

    /// Signs in to the daemon that answered (`SignInPlan` decides how) and
    /// loads its page. With a sign-in code, the page loads with it; without
    /// one (the CLI gave none) it loads anyway: the cookie from last time may
    /// still work, and if not, the 401 asks for a code again. A daemon that
    /// Claude Science's own app started is signed in to through its own small
    /// page first, and when there is no way in at all Capsid only reads.
    private func signIn(daemon: CLIStatus) async {
        guard let port = daemon.port else {
            // Running, but no port is named: Capsid doesn't guess one.
            fail(DaemonError.noPort.sentence, temporary: true)
            return
        }
        signingIn = true
        defer {
            signingIn = false
            sleeper.pageChanged()
        }
        self.port = port
        host = DaemonHost.name(for: daemon.urlHost)
        signedInDaemon = daemon
        guard let root = URL(string: "http://\(host):\(port)/") else {
            fail("Couldn't build Claude Science's address.", temporary: false)
            return
        }
        // Reopen where the user was (Web/LastSession.swift), unless a link
        // already asked for somewhere. The database is asked while the
        // sign-in code is fetched, so a launch waits for neither. The code is
        // asked for whatever `require_token` says: the browser-tab daemon
        // reports it too, and the code is how Capsid has always signed in.
        let owned = await appOwned()
        async let code = Self.codeIfWanted(true)
        let remembered = pendingURL == nil
            ? await lastSession.reopenURL(port: port, host: host, isKnown: LastSession.databaseKnows) : nil
        // Beside the app, a first ask that gave no code is asked once more after 1.5 s: a daemon too busy to answer
        // one `claude-science url` answers the next. The launcher that opens a tab is asked once, as always.
        let nonce = await SignInPlan.code(first: await code, appOwned: owned, askAgain: { await DaemonController.freshNonce() },
                                          wait: { try? await Task.sleep(for: $0) })
        // A link that came before the port was known was built for the usual
        // one; it belongs on the port the daemon actually uses. One that comes
        // while the above runs waits for this, and wins over the remembered
        // session.
        let link = pendingURL.map { Self.canonical(Self.moving($0, toPort: port), host: host) }
        pendingURL = nil
        let destination = LastSession.launchDestination(link: link, remembered: remembered, root: root, port: port)

        switch SignInPlan.decide(appOwned: owned, nonce: nonce) {
        case .page(let nonce):
            webView.load(URLRequest(url: nonce.map { addingLoginNonce($0, to: destination) } ?? destination))
        case .apiMe(let nonce):
            await signInThroughAPIMe(nonce: nonce, port: port)
            webView.load(URLRequest(url: destination))
        }
    }

    private static func codeIfWanted(_ wanted: Bool) async -> String? {
        wanted ? await DaemonController.freshNonce() : nil
    }

    /// Whether the daemon belongs to Claude Science's own app (`SignInPlan.appOwned`).
    /// The install is looked at off the main thread.
    private func appOwned() async -> Bool {
        SignInPlan.appOwned(daemon: signedInDaemon, install: await DaemonController.installedOpens(), handoverSeen: handover.seen)
    }

    /// The daemon's own sign-in page, for a daemon the app started: load
    /// `/api/me?nonce=<code>`, press its one Sign in button, and let it end on
    /// its JSON. Every step is bounded and none is final: whatever happens,
    /// the page loads next, and a 401 there asks for a new code the usual way.
    private func signInThroughAPIMe(nonce: String, port: Int) async {
        guard let url = SignInPlan.apiMeURL(host: host, port: port, nonce: nonce) else { return }
        webView.load(URLRequest(url: url))
        await settleOnSignInStep(upTo: .seconds(10))
        let answer = try? await webView.callAsyncJavaScript(SignInScript.press, arguments: [:], in: nil,
                                                            contentWorld: .defaultClient)
        let pressed = (answer as? Bool) == true
        Logger.web.info("The sign-in page's button \(pressed ? "was pressed" : "did not show", privacy: .public)")
        if pressed { await settleOnSignInStep(upTo: .seconds(5), expectingAnswer: true) }
    }

    /// Waits for the web view to stop loading on the sign-in step's address
    /// (or, after the button, to stop loading at all), or `limit`.
    private func settleOnSignInStep(upTo limit: Duration, expectingAnswer: Bool = false) async {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            if !webView.isLoading, expectingAnswer || SignInPlan.isSignInStep(webView.url) { return }
        }
    }

    /// There is no way in right now: Capsid reads the database only, and says so once. A failure that may
    /// pass (a daemon too busy to give a code answers the next try), so the quiet tries keep going
    /// (Web/StartRetry.swift) and sign in as soon as a code comes.
    private func enterReadOnly(_ reason: ReadOnlyReason) {
        Logger.web.notice("Only reading: \(reason.phrase, privacy: .public)")
        fail(CompanionSentence.readOnly, temporary: true, companion: .readOnly(reason))
        if !readOnlyAnnounced {
            readOnlyAnnounced = true
            LabModel.shared.post(CompanionSentence.readOnlyNotice)
        }
    }

    /// The Open Claude Science button. While the window waits for the app's
    /// daemon, the button starts the app in the background (Capsid stays in
    /// front, and the quick tries start over, since the user just started it);
    /// while Capsid only reads, it is the way to the session, so the app comes forward.
    func openScience() {
        if companion == .waitingForApp {
            ScienceApp.open(.startServer)
            retry.stop(resetting: true)
            retry.begin()
        } else {
            ScienceApp.open(.show)
        }
    }

    /// The page showed the dialog that says Claude Science now opens in its
    /// own window (Web/HandoverWatch.swift).
    func handoverShown() {
        handover.dialogShown()
    }

    /// `url` on `port`, when it is a localhost address on another one.
    static func moving(_ url: URL, toPort port: Int) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["localhost", "127.0.0.1"].contains(parts.host ?? ""), parts.port != port else { return url }
        parts.port = port
        return parts.url ?? url
    }

    // MARK: Navigation

    /// Loads a daemon URL in the one web view. The navigation delegate still
    /// routes it, so a URL that isn't the daemon's ends up in a Browser window.
    func load(_ url: URL) {
        // Asleep or waking, the link waits for the sign-in like one at launch:
        // it wins over where the page slept, and a window shown wakes the page.
        guard port != nil, !signingIn, !waking, status != .asleep else {
            pendingURL = url
            return
        }
        webView.load(URLRequest(url: Self.canonical(url, host: host)))
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
        // The daemon's own sign-in step refused its code: that leg is over, and
        // the page loads next with the usual route (a 401 there comes back
        // here). It takes none of this function's one-per-30-seconds.
        if SignInPlan.isSignInStep(url) {
            Logger.web.notice("The sign-in page refused its code")
            return false
        }
        let now = ContinuousClock.now
        if let last = lastSignInRetry, now - last < Self.signInRetryInterval {
            Logger.web.error("The daemon refused the sign-in again")
            guard status == .starting else { return false }
            fail("Claude Science didn't accept the sign-in. Try again.", temporary: false)
            return true
        }
        lastSignInRetry = now
        Task {
            // `claude-science url` asks the daemon too, so a frozen daemon
            // fails here as well: a failure that may pass. Beside Claude
            // Science's own app a missing code is asked for once more before
            // it is taken to mean there is none.
            let owned = await appOwned()
            let nonce = await SignInPlan.code(first: await DaemonController.freshNonce(), appOwned: owned,
                                              askAgain: { await DaemonController.freshNonce() },
                                              wait: { try? await Task.sleep(for: $0) })
            guard let nonce else {
                switch SignInPlan.outcomeWithoutCode(appOwned: owned) {
                case .readOnly(let reason): enterReadOnly(reason)
                case .retryLater: fail("Couldn't get a sign-in code from Claude Science.", temporary: true)
                }
                return
            }
            webView.load(URLRequest(url: addingLoginNonce(nonce, to: url)))
        }
        return true
    }

    /// An API read from the page came back 401: after a restart the page
    /// often shows Claude Science's own "Sign in" card, and pressing its button
    /// goes straight back in (Sam, 2026-09-29), with no password or consent
    /// asked. So Bench presses it, as he would: the first visible button
    /// reading "Sign in", looked for over six seconds while the page draws.
    /// Without one, it signs in again with a fresh `claude-science url` code.
    /// At most once in ten minutes, so it never keeps pressing or reloading.
    func sessionLost() {
        let now = ContinuousClock.now
        if let last = lastSessionRecovery, now - last < .seconds(600) { return }
        guard let url = webView.url, WebRoute.classify(url, daemonPort: port) == .daemon else { return }
        lastSessionRecovery = now
        Task {
            if await pressSignIn() {
                Logger.web.info("Pressed Claude Science's Sign in after a refused API read")
                try? await Task.sleep(for: .seconds(4))
                PlanUsageModel.shared.refresh()
                return
            }
            // A designed branch, not a change (DESIGN.md, Daemon and sign-in):
            // nothing is noted for Diagnostics.
            Logger.web.info("An API read was refused and no Sign in button showed; signing in again")
            guard let nonce = await DaemonController.freshNonce() else { return }
            webView.load(URLRequest(url: addingLoginNonce(nonce, to: Self.canonical(url, host: host))))
        }
    }

    /// Presses the page's visible "Sign in" button, if one appears within six
    /// seconds. Runs in Bench's own script world, which sees the same page.
    private func pressSignIn() async -> Bool {
        let result = try? await webView.callAsyncJavaScript(SignInScript.press, arguments: [:], in: nil, contentWorld: .defaultClient)
        return (result as? Bool) == true
    }

    /// Whether the page shows its "Sign in" button right now (Diagnostics).
    /// Looks only; it never presses it.
    func signInButtonIsShowing() async throws -> Bool {
        guard status == .ready else { throw WebAPIError.notReady }
        let value = try await webView.callAsyncJavaScript(SignInScript.look, arguments: [:], in: nil, contentWorld: .defaultClient)
        return (value as? Bool) == true
    }

    /// The words selected in the page, for Add Selection to Shelf
    /// (Shelf/ConversationMenu.swift): `window.getSelection()` read in Capsid's
    /// own content world, at most `limit` characters, or nil when nothing is
    /// selected, the page isn't up, or it doesn't answer within two seconds.
    /// It reads no element and no selector of the page; the words go to the
    /// caller and nowhere else, and nothing of them is logged.
    func selectedWords(limit: Int) async -> String? {
        guard status == .ready, limit > 0 else { return nil }
        let view = webView
        let text = try? await WriteDeadline.bridge(.seconds(2)) { () async throws -> String in
            let value = try await view.callAsyncJavaScript(SelectedWordsScript.read, arguments: ["limit": limit], in: nil,
                                                           contentWorld: ConversationMenu.world)
            return (value as? String) ?? ""
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(text.prefix(limit))
    }

    /// The first daemon page to finish loading means we are in.
    func mainFrameFinished(at url: URL?) {
        guard WebRoute.classify(url, daemonPort: port) == .daemon else { return }
        // The daemon's own sign-in step (`/api/me`) is not the page.
        guard !SignInPlan.isSignInStep(url) else { return }
        status = .ready
        // Looks once, quietly, when Claude Science's version has changed (App/CompatWatch.swift).
        CompatWatch.shared.pageReady()
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
        if StartRetry.isUnreachable(failure), let port {
            if handover.seen {
                // The daemon went when the app took over: not a daemon that
                // is slow, but one the app starts. The same status-only tries wait for it.
                fail(CompanionSentence.waitingForApp, temporary: true, companion: .waitingForApp)
            } else {
                fail("Claude Science isn't responding on port \(port).", temporary: true)
            }
        } else {
            fail("Couldn't open Claude Science: \(failure.localizedDescription)", temporary: false)
        }
    }

    /// WebKit ended the page's process (memory, or a crash). A reload starts a
    /// new one.
    func contentProcessTerminated() {
        Logger.web.error("The web content process ended; reloading")
        reload()
    }

    /// Cookies are kept per host, so 127.0.0.1 and localhost would be two
    /// sign-ins. Everything Capsid loads uses the one host the daemon names
    /// (`daemon.url_host`; `localhost` when it names none): a daemon that moved
    /// to 127.0.0.1 would answer a page asked for on `localhost` with
    /// whatever else listens there.
    static func canonical(_ url: URL, host: String = DaemonHost.usual) -> URL {
        DaemonHost.canonical(url, host: host)
    }

    // MARK: Sleeping (Web/PageSleep.swift)

    /// For an action that needs the page: a write through it, a reply, a phone
    /// request. The page is held awake for `body`. A page that sleeps is woken
    /// first, and `body` waits up to `limit` for it to be ready (it finds the
    /// page as it is then, and says not ready as it always has if it isn't). An
    /// awake page, or one starting or failed for its own reasons, runs `body` at
    /// once, exactly as before: with the setting on, the default, nothing here
    /// waits or wakes.
    func withPage<T>(waitingUpTo limit: Duration = .seconds(30), _ body: () async throws -> T) async rethrows -> T {
        let wasAsleep = status == .asleep || waking
        sleeper.beginUse()
        defer { sleeper.endUse() }
        if wasAsleep { await untilAwake(upTo: limit) }
        return try await body()
    }

    /// For a call into the ready page (a read, a write, a file's chunks): the
    /// page doesn't sleep under it. It neither wakes the page nor starts the
    /// grace over, so reads made on a timer don't keep a closed window's page up.
    func duringCall<T>(_ body: () async throws -> T) async rethrows -> T {
        sleeper.beginCall()
        defer { sleeper.endCall() }
        return try await body()
    }

    /// Waits while a wake is under way, up to `limit`.
    private func untilAwake(upTo limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while status == .asleep || waking || status == .starting, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// The main window opened or closed (`MainWindowController`).
    func mainWindow(isOpen: Bool) {
        guard Demo.mode == nil else { return }
        startWatchingReaderWindows()
        sleeper.setWindowOpen(isOpen)
    }

    /// Results, the Shelf, Compare, Reference and Ask Another Model read
    /// through the page: while one is open the page is held awake, and wakes
    /// if it slept (`PageReadingWindow`).
    private var readerWindowsWatch: [NSObjectProtocol] = []
    private var holdingForReaderWindows = false

    private func startWatchingReaderWindows() {
        guard readerWindowsWatch.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification] {
            readerWindowsWatch.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let closing = name == NSWindow.willCloseNotification ? note.object as? NSWindow : nil
                MainActor.assumeIsolated { WebContainer.shared.readerWindowsChanged(closing: closing) }
            })
        }
    }

    private func readerWindowsChanged(closing: NSWindow?) {
        let open = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.delegate is PageReadingWindow }
        guard open != holdingForReaderWindows else { return }
        holdingForReaderWindows = open
        if open { sleeper.beginUse() } else { sleeper.endUse() }
    }

    /// The Settings switch changed.
    func keepLoadedChanged() {
        sleeper.setKeepLoaded(PageSleepSetting.keepsLoaded())
    }

    /// Unloads the page, as a quit leaves it: where it was is kept (the address
    /// watch has already written it for the next launch, and the wake goes back
    /// to it), the cookie stays in WebKit's store, and the web view is let go so
    /// its web content process ends. An empty one, made the same way, takes its
    /// place; nothing is loaded in it until the wake.
    private func sleep() {
        guard status == .ready, !signingIn, startTask == nil else { return }
        let old = webView
        if let url = old.url, WebRoute.classify(url, daemonPort: port) == .daemon, !SignInPlan.isSignInStep(url) {
            sleptAt = url
        }
        Logger.web.notice("The window is closed: the page sleeps")
        lastSlept = Date()
        // Not a blank page in the same web view: measured on 2026-11-13, that
        // left its process at 153 MB. Letting it go ends the process.
        replaceWebView()
        status = .asleep
    }

    /// Lets the web view go, so its web content process ends, and puts an
    /// empty one, made the same way, in its place.
    private func replaceWebView() {
        let old = webView
        pageWatches = []
        old.stopLoading()
        old.navigationDelegate = nil
        old.uiDelegate = nil
        old.configuration.userContentController.removeAllScriptMessageHandlers()
        old.configuration.userContentController.removeAllUserScripts()
        if let window = old.window, window.firstResponder === old { window.makeFirstResponder(nil) }
        let fresh = Self.makeWebView(notifications: notifications, handoverWatch: handoverWatch, tabMenu: tabMenu,
                                     shelfMenu: shelfMenu, modelMenu: modelMenu)
        // SwiftUI lets the old one go when it next draws the window; a closed
        // window may not draw, so it is taken out now.
        old.removeFromSuperview()
        webView = fresh
        finder = PageFinder(webView: fresh)
        watch(fresh)
    }

    /// Loads the page again where it slept, signed in the way a launch signs
    /// in (a fresh code on the address, so no Sign in card), unless a link
    /// asked for somewhere else meanwhile.
    private func wake() {
        guard status == .asleep else { return }
        Logger.web.notice("The page wakes")
        waking = true
        if pendingURL == nil { pendingURL = sleptAt }
        sleptAt = nil
        // For the window or the switch, as Try again does: the daemon is started
        // if it isn't running (never beside Claude Science's own app). For an
        // action alone, only a daemon that is running is signed in to.
        if sleeper.wantsPageForItself {
            begin(found: nil)
            return
        }
        status = .starting
        Task {
            let daemon = await DaemonController.runningStatus()
            guard waking, status == .starting, startTask == nil else { return }
            if let daemon {
                begin(found: daemon)
            } else if sleeper.wantsPageForItself {
                begin(found: nil)
            } else {
                Logger.web.notice("The page stays asleep: Claude Science isn't running")
                backToSleep()
            }
        }
    }

    /// A wake that didn't come up, with nothing on screen wanting the page.
    private func backToSleep() {
        if sleptAt == nil, let url = pendingURL, WebRoute.classify(url, daemonPort: port) == .daemon { sleptAt = url }
        pendingURL = nil
        waking = false
        // Whatever the attempt loaded goes with it.
        if webView.url != nil { replaceWebView() }
        status = .asleep
    }

    // MARK: Zoom

    // The main window remembers its zoom; the other windows' is per window
    // (WebPageWindow).
    func zoomIn() { setZoom(PageZoom.zoomedIn(webView.pageZoom)) }
    func zoomOut() { setZoom(PageZoom.zoomedOut(webView.pageZoom)) }
    func resetZoom() { setZoom(PageZoom.actualSize) }

    private func setZoom(_ value: Double) {
        let zoom = PageZoom.clamped(value)
        webView.pageZoom = zoom
        UserDefaults.standard.set(zoom, forKey: SettingsKey.pageZoom)
    }

    private static func storedZoom() -> Double {
        let stored = UserDefaults.standard.object(forKey: SettingsKey.pageZoom) as? Double ?? PageZoom.actualSize
        return min(max(stored, PageZoom.range.lowerBound), PageZoom.range.upperBound)
    }
}

/// The page's "Sign in" button, as a script: one finder, shared by the press
/// and by Diagnostics' look, so the look checks what the press would find.
enum SignInScript {
    /// `benchFindSignIn()`: the first visible button or link reading exactly
    /// "Sign in", or null.
    static let finder = #"""
    function benchFindSignIn() {
        const found = [...document.querySelectorAll("button, a")].find(el => {
            const box = el.getBoundingClientRect();
            return (el.textContent || "").trim() === "Sign in" && box.width > 0 && box.height > 0;
        });
        return found || null;
    }
    """#

    /// Looks for the button every half second for six seconds, and presses it.
    static let press = finder + #"""

    for (let i = 0; i < 12; i++) {
        const target = benchFindSignIn();
        if (target) { target.click(); return true; }
        await new Promise(resolve => setTimeout(resolve, 500));
    }
    return false;
    """#

    /// Looks once, and presses nothing.
    static let look = finder + #"""

    return benchFindSignIn() !== null;
    """#
}
