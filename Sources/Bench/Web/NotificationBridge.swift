// NotificationBridge.swift — gives Claude Science the desktop-notification
// API WebKit lacks (DESIGN.md, Notification bridge). A user script defines
// `window.Notification`, and each notification it makes is forwarded to the
// Router, which shows it in the Lab panel. This is the one thing Bench adds
// to the page.
import Foundation
import os
import WebKit

@MainActor
final class NotificationBridge {
    private static let handlerName = "benchNotify"

    private let daemonPort: @MainActor () -> Int?

    init(daemonPort: @escaping @MainActor () -> Int?) {
        self.daemonPort = daemonPort
    }

    /// Adds the script and its message handler. The controller keeps a strong
    /// reference to the handler, so it gets a proxy that only holds this
    /// bridge weakly, and the bridge can go away with its owner.
    func install(on controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(WeakScriptHandler(bridge: self), name: Self.handlerName)
    }

    /// Runs the `onclick` of the page's notification with this id.
    func click(_ id: String, in webView: WKWebView) {
        // A bare string needs `.fragmentsAllowed`, or JSONSerialization raises
        // an Objective-C exception instead of throwing.
        guard let data = try? JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed]),
              let quoted = String(data: data, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript("window.__benchNotificationClicked(\(quoted))", completionHandler: nil)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        // The script also runs in pop-ups, and a pop-up can be someone else's
        // page: only Claude Science's own may put a card in the panel.
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame,
              WebRoute.isDaemonOrigin(scheme: origin.protocol, host: origin.host, port: origin.port, daemonPort: daemonPort()),
              let body = message.body as? [String: Any],
              let id = body["id"] as? String
        else {
            Logger.web.notice("Ignored a notification message")
            return
        }
        // The page withdrew it: its card goes, so Open can't call a
        // notification that no longer exists.
        if body["closed"] as? Bool == true {
            Router.shared.webNotificationClosed(id)
            return
        }

        let tag = (body["tag"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        Router.shared.webNotificationArrived(WebNotification(
            id: id,
            title: body["title"] as? String ?? "",
            body: body["body"] as? String ?? "",
            tag: tag,
            requireInteraction: body["requireInteraction"] as? Bool ?? false,
            receivedAt: Date()))
    }

    // MARK: The page's side

    /// `window.Notification`. Permission is always granted, since Bench shows
    /// the notification itself. Instances are kept by id so native code can
    /// click one, and the newest 200 are kept so a long session can't grow it
    /// without bound.
    private static let script = #"""
    (() => {
      "use strict";
      if (location.protocol !== "http:" || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.benchNotify;
      if (!handler || window.__benchNotificationClicked) return;

      const live = new Map();
      const ids = new WeakMap();
      let counter = 0;

      class BenchNotification extends EventTarget {
        static get permission() { return "granted"; }
        static get maxActions() { return 0; }
        static requestPermission(callback) {
          if (typeof callback === "function") callback("granted");
          return Promise.resolve("granted");
        }

        constructor(title, options) {
          super();
          const settings = options || {};
          const id = `${++counter}-${Math.random().toString(36).slice(2, 10)}`;
          ids.set(this, id);
          this.title = String(title);
          this.body = settings.body == null ? "" : String(settings.body);
          this.tag = settings.tag == null ? "" : String(settings.tag);
          this.data = settings.data === undefined ? null : settings.data;
          this.requireInteraction = Boolean(settings.requireInteraction);

          for (const type of ["click", "close", "show", "error"]) {
            this["on" + type] = null;
            this.addEventListener(type, (event) => {
              const inline = this["on" + type];
              if (typeof inline === "function") inline.call(this, event);
            });
          }

          live.set(id, this);
          if (live.size > 200) live.delete(live.keys().next().value);
          handler.postMessage({
            id,
            title: this.title,
            body: this.body,
            tag: this.tag,
            requireInteraction: this.requireInteraction,
          });
          setTimeout(() => this.dispatchEvent(new Event("show")), 0);
        }

        close() {
          const id = ids.get(this);
          if (!live.delete(id)) return;
          handler.postMessage({ id, closed: true });
          this.dispatchEvent(new Event("close"));
        }
      }

      Object.defineProperty(window, "Notification", { value: BenchNotification, writable: true, configurable: true });
      Object.defineProperty(window, "__benchNotificationClicked", {
        value(id) {
          const notification = live.get(id);
          if (notification) notification.dispatchEvent(new Event("click"));
        },
      });
    })();
    """#
}

/// What the user content controller holds in place of the bridge itself.
@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var bridge: NotificationBridge?

    init(bridge: NotificationBridge) {
        self.bridge = bridge
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        bridge?.receive(message)
    }
}
