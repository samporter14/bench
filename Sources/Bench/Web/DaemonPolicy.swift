// DaemonPolicy.swift — the rules for living beside Claude Science's own app
// (DESIGN.md, Daemon and sign-in; 1.0 spikes S1), as pure functions the tests
// run over every combination. `DaemonController` and `WebContainer` do the
// running and the loading; the decisions are here:
//
//   - whether Capsid may start a daemon (`StartPlan`): never beside the app
//     that starts its own;
//   - how it signs in, and when it can't (`SignInPlan`): then it is a
//     read-only companion (`ReadOnlyReason`);
//   - which host the daemon's address uses (`DaemonHost`);
//   - the sentences all of that says (`CompanionSentence`).
import Foundation

// MARK: Starting

/// What `claude-science status` answered, as far as starting goes.
enum StatusAnswer: Equatable, Sendable {
    case running(CLIStatus)
    /// An explicit "running": false, the one answer that may allow a start.
    case notRunning
    /// No answer, an unreadable one, or no tool.
    case failed
}

/// What to do about the daemon. `serve` is the only thing here that changes
/// anything, and it is the last resort.
enum StartPlan: Equatable, Sendable {
    /// It is running: sign in to it and start nothing.
    case attach(CLIStatus)
    /// `claude-science serve --no-browser --detached`, once (what Capsid has
    /// always done when nothing runs).
    case serve
    /// Claude Science's own app starts its daemon. Capsid waits for it and
    /// says so; it never starts one beside it (the app adopts a running
    /// daemon and would be pinned to whatever version this one is).
    case waitForApp(WaitReason)
    /// The status couldn't be read: a second daemon on top of a running one
    /// is worse than an error.
    case giveUp

    enum WaitReason: Equatable, Sendable {
        /// The installed app is `com.anthropic.claudescience`.
        case ownWindowApp
        /// The last running daemon said it was the app's child (the app has
        /// quit since; Capsid starts no daemon when it does).
        case appChild
        /// The page showed the handover dialog this run.
        case handover
    }

    static func decide(_ answer: StatusAnswer, install: ScienceInstall.Opens,
                       lastLaunchContext: String?, handoverSeen: Bool) -> StartPlan {
        switch answer {
        case .running(let status):
            return .attach(status)
        case .failed:
            return .giveUp
        case .notRunning:
            if install == .ownWindow { return .waitForApp(.ownWindowApp) }
            if lastLaunchContext == CLIStatus.appChild { return .waitForApp(.appChild) }
            if handoverSeen { return .waitForApp(.handover) }
            return .serve
        }
    }
}

// MARK: Signing in

/// Why Capsid can't sign in to the daemon, so it only reads.
enum ReadOnlyReason: Equatable, Sendable {
    /// `claude-science url` gave no code (asked twice, 1.5 s apart) and the page refused the cookie from last
    /// time (a daemon started without its control socket answers none).
    case noCode

    var phrase: String {
        switch self {
        case .noCode: "the daemon gave no sign-in code"
        }
    }
}

/// How the main window signs in to a daemon that answered.
enum SignInPlan: Equatable, Sendable {
    /// Load the page with the code on it (today's way); without a code, load
    /// it anyway, since the cookie from last time may still be good.
    case page(nonce: String?)
    /// A daemon the app started: its own small page at `/api/me?nonce=<code>`
    /// has one Sign in button and ends on JSON; then the page loads.
    case apiMe(nonce: String)

    /// `appOwned`: the daemon is the app's child, or the own-window app is
    /// installed, or the page has shown the handover dialog.
    ///
    /// `require_token` is no part of this, and never was a reason to stop: the browser-tab daemon reports it
    /// too, and the one-time code signs in to it as it always has (the first cut went read-only on it, on Sam's
    /// Mac, 2026-10-22). Beside the app, with no code even after asking again, the page is loaded without one: the
    /// cookie from last time may still be good, and if it is not, the page's 401 asks for a code again and the
    /// read-only companion (`outcomeWithoutCode`) is where that ends, not here. One failed `claude-science url`
    /// (a busy daemon) used to end there for good.
    static func decide(appOwned: Bool, nonce: String?) -> SignInPlan {
        guard appOwned, let nonce else { return .page(nonce: nonce) }
        return .apiMe(nonce: nonce)
    }

    /// How long after a first ask that gave no code the second one comes, beside the app.
    static let askAgainAfter = Duration.milliseconds(1500)

    /// The one-time code for signing in. `first` is what the first ask gave. With none, a daemon that is the
    /// app's is asked once more after `askAgainAfter` (a busy daemon fails one `claude-science url` and answers
    /// the next); with the launcher that opens a tab, nothing is asked twice, as it always was.
    static func code(first: String?, appOwned: Bool, askAgain: @Sendable () async -> String?,
                     wait: @Sendable (Duration) async -> Void) async -> String? {
        if let first { return first }
        guard appOwned else { return nil }
        await wait(askAgainAfter)
        return await askAgain()
    }

    /// Whether the daemon belongs to Claude Science's own app, so signing in
    /// to it is not the usual way: it is the app's child, or that app is
    /// installed, or the page said Claude Science now opens in its own window.
    static func appOwned(daemon: CLIStatus?, install: ScienceInstall.Opens, handoverSeen: Bool) -> Bool {
        daemon?.isAppChild == true || install == .ownWindow || handoverSeen
    }

    /// What a refused load becomes when no code can be had to try again with.
    /// Beside the app it is the end of signing in (the read-only companion);
    /// with the launcher that opens a tab it is a failure that may pass, as
    /// it always was.
    static func outcomeWithoutCode(appOwned: Bool) -> Outcome {
        appOwned ? .readOnly(.noCode) : .retryLater
    }

    enum Outcome: Equatable, Sendable {
        case readOnly(ReadOnlyReason)
        case retryLater
    }

    /// `http://<host>:<port>/api/me?nonce=<code>`.
    static func apiMeURL(host: String, port: Int, nonce: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = host
        parts.port = port
        parts.path = "/api/me"
        parts.queryItems = [URLQueryItem(name: "nonce", value: nonce)]
        return parts.url
    }

    /// The sign-in step's own address, which is never a page to show: the
    /// window isn't ready when it finishes, and a JSON answer there is shown,
    /// never saved as a file.
    static func isSignInStep(_ url: URL?) -> Bool {
        guard let url, DaemonHost.isLoopback(url.host) else { return false }
        return url.path == "/api/me"
    }
}

// MARK: The host

enum DaemonHost {
    static let usual = "localhost"
    static let numeric = "127.0.0.1"

    /// The host Capsid loads the daemon from: what `daemon.url_host` names
    /// when it is one of the two loopback names Capsid treats as the daemon's
    /// own, else the usual `localhost`. (Cookies are kept per host, so one
    /// host serves every page.)
    static func name(for urlHost: String?) -> String {
        urlHost?.lowercased() == numeric ? numeric : usual
    }

    static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == usual || host == numeric
    }

    /// `url` on `host`, when it is a loopback address on the other name.
    static func canonical(_ url: URL, host: String) -> URL {
        guard isLoopback(url.host), url.host?.lowercased() != host,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.host = host
        return parts.url ?? url
    }
}

// MARK: Sentences

/// What Capsid says about all of this, word for word, so the tests hold it.
enum CompanionSentence {
    /// The window's failure while the app owns the server.
    static let waitingForApp = "Claude Science runs its own server now. Open Claude Science to start it."

    /// The window's note while Capsid can't sign in, and the card's title and detail.
    static let readOnlyTitle = "Capsid can't sign in to Claude Science's own server"
    static let readOnlyDetail = "Everything from your sessions' database keeps working; actions open Claude Science."
    static var readOnly: String { readOnlyTitle + ". " + readOnlyDetail }

    /// The one card when the page says Claude Science now opens in its own
    /// window: its title, then what stays and what changed.
    static let handoverTitle = "Claude Science now opens in its own window"
    static let handoverDetail = "Capsid keeps working beside it."
    static let handoverChanged = "It no longer starts Claude Science's server: open Claude Science to start it."
    static var handover: String { handoverTitle + ". " + handoverDetail }

    static let openButton = "Open Claude Science"
}

extension CompanionSentence {
    /// The card that says, once, that Capsid only reads.
    static var readOnlyNotice: LabNotice {
        LabNotice(id: "read-only-companion", symbol: "lock", caption: "Claude Science",
                  title: readOnlyTitle, detail: readOnlyDetail, lifetime: .seconds(20))
    }
}
