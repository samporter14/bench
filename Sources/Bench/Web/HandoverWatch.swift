// HandoverWatch.swift — hears the page say that Claude Science now opens in
// its own window (DESIGN.md, Daemon and sign-in; 1.0 spikes S1). When Claude
// Science switches from a browser tab to its own app window, the page shows
// a dialog (`[data-testid="restarting-dialog"]`, "Claude Science now opens
// in its own window") and the daemon restarts as the app's child. A user
// script watches for that dialog and tells Capsid once; the dialog's words
// are never read, only that it is on screen.
//
// Built like the notification bridge (Web/NotificationBridge.swift): one user
// script in the main frame, one message handler held weakly, and a message
// counts only from the daemon's own page.
import Foundation
import os
import WebKit

@MainActor
final class HandoverWatch {
    static let handlerName = "benchHandover"

    private let daemonPort: @MainActor () -> Int?
    private let shown: @MainActor () -> Void

    init(daemonPort: @escaping @MainActor () -> Int?, shown: @escaping @MainActor () -> Void) {
        self.daemonPort = daemonPort
        self.shown = shown
    }

    func install(on controller: WKUserContentController) {
        // At document end: the dialog is part of the page the app draws, so
        // there is nothing to see before it.
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.add(WeakHandoverHandler(watch: self), name: Self.handlerName)
    }

    /// Whether a message is the daemon's own page saying the dialog is up.
    nonisolated static func accepts(isMainFrame: Bool, scheme: String?, host: String?, port: Int?,
                                    daemonPort: Int?, body: Any) -> Bool {
        guard isMainFrame,
              WebRoute.isDaemonOrigin(scheme: scheme, host: host, port: port, daemonPort: daemonPort),
              let fields = body as? [String: Any], fields["shown"] as? Bool == true else { return false }
        return true
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard Self.accepts(isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host,
                           port: origin.port, daemonPort: daemonPort(), body: message.body) else {
            Logger.web.notice("Ignored a handover message")
            return
        }
        shown()
    }

    // MARK: The page's side

    /// Looks for the dialog after the page changes, at most once a second
    /// (a page that streams text changes all the time), and says so once. A
    /// check is one selector; the observer is dropped as soon as it has found it.
    nonisolated static let script = #"""
    (() => {
      "use strict";
      if (location.protocol !== "http:" || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.benchHandover;
      if (!handler || window.__benchHandoverWatch) return;
      Object.defineProperty(window, "__benchHandoverWatch", { value: true });

      let told = false;
      let timer = null;
      const look = () => {
        timer = null;
        if (told || !document.querySelector('[data-testid="restarting-dialog"]')) return;
        told = true;
        observer.disconnect();
        handler.postMessage({ shown: true });
      };
      const observer = new MutationObserver(() => {
        if (timer === null && !told) timer = setTimeout(look, 1000);
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
      look();
    })();
    """#
}

/// What the user content controller holds in place of the watch itself.
@MainActor
private final class WeakHandoverHandler: NSObject, WKScriptMessageHandler {
    private weak var watch: HandoverWatch?

    init(watch: HandoverWatch) {
        self.watch = watch
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        watch?.receive(message)
    }
}

// MARK: What Capsid does about it

/// The handover, once per run: stop the reconnect tries, say it in one card,
/// and watch for the daemon the app starts. The effects come in as closures
/// so the tests run it without a window.
@MainActor
final class Handover {
    /// The page showed the dialog this run. `StartPlan` reads it: with Claude
    /// Science in its own window, Capsid starts no daemon of its own.
    private(set) var seen = false
    /// The new daemon hasn't been signed in to yet.
    var waitingForNewDaemon = false

    private let stopRetries: () -> Void
    private let post: (LabNotice) -> Void
    private let watchForDaemon: () -> Void

    init(stopRetries: @escaping () -> Void, post: @escaping (LabNotice) -> Void, watchForDaemon: @escaping () -> Void) {
        self.stopRetries = stopRetries
        self.post = post
        self.watchForDaemon = watchForDaemon
    }

    /// The dialog is on screen. Only the first one counts: the page says it
    /// again on every load until the daemon is gone.
    func dialogShown() {
        guard !seen else { return }
        seen = true
        waitingForNewDaemon = true
        stopRetries()
        post(Self.notice)
        watchForDaemon()
    }

    /// The one card: what changed and what didn't, in the Solanum voice.
    nonisolated static var notice: LabNotice {
        LabNotice(id: "handover-own-window", symbol: "macwindow", caption: "Claude Science",
                  title: CompanionSentence.handoverTitle,
                  detail: CompanionSentence.handoverDetail + " " + CompanionSentence.handoverChanged,
                  lifetime: .seconds(20))
    }

    /// Whether `now` is a different daemon from the one signed in to: the app
    /// started its own (another process, port or starter).
    nonisolated static func isNewDaemon(_ now: CLIStatus, than old: CLIStatus?) -> Bool {
        guard let old else { return true }
        return now.pid != old.pid || now.port != old.port || now.isAppChild != old.isAppChild
    }
}
