// WebUIDelegate.swift — the native side of a page's UI: dialogs, the file
// picker, camera and microphone, and new windows (DESIGN.md, Web routing
// policy). Every web view in Bench uses this one class; only `role` differs.
import AppKit
import WebKit

@MainActor
final class WebUIDelegate: NSObject, WKUIDelegate {
    enum Role {
        /// The one main web view: the routing table decides every new window.
        case main
        /// A pop-up. The daemon's own pages follow the routing table, but a
        /// page we don't own (an OAuth site) gets a real child window of its
        /// own, so the opener chain it relies on stays whole.
        case popup
        /// The Browser and Preview windows: links stay inside the window.
        case contained
    }

    private let role: Role
    /// What to do when the page closes its own window.
    var onClose: (() -> Void)?

    init(role: Role) {
        self.role = role
    }

    // MARK: New windows

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let daemonPort = WebContainer.shared.port
        let url = navigationAction.request.url
        let target = WebRoute.classify(url, daemonPort: daemonPort)

        switch role {
        case .contained:
            // Links stay in this window, except the daemon's (the one main
            // view) and other schemes (macOS).
            switch target {
            case .inert:
                break
            case .daemon, .external:
                if let url { LinkDispatcher.open(url, as: target) }
            case .preview, .web:
                webView.load(navigationAction.request)
            }
            return nil

        case .popup where !Self.isDaemonFrame(navigationAction.sourceFrame, daemonPort: daemonPort):
            return WebWindows.shared.openPopup(configuration: configuration, features: windowFeatures)

        case .main, .popup:
            // A blank window is Claude Science's pop-out pool or a connector
            // sign-in: it needs a real window.opener, so it gets a real child.
            if target == .inert {
                return WebWindows.shared.openPopup(configuration: configuration, features: windowFeatures)
            }
            if let url { LinkDispatcher.open(url, as: target) }
            return nil
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        onClose?()
    }

    private static func isDaemonFrame(_ frame: WKFrameInfo, daemonPort: Int?) -> Bool {
        let origin = frame.securityOrigin
        return WebRoute.isDaemonOrigin(scheme: origin.protocol, host: origin.host, port: origin.port, daemonPort: daemonPort)
    }

    // MARK: Dialogs

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        _ = await present(alert, over: webView)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await present(alert, over: webView) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = makeAlert(message: prompt, frame: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return await present(alert, over: webView) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// The page's text is the headline. A page that isn't Claude Science also
    /// says who is asking, so a dialog can't pass for the app's own.
    private func makeAlert(message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        if !WebRoute.isDaemonOrigin(scheme: frame.securityOrigin.protocol, host: frame.securityOrigin.host,
                                    port: frame.securityOrigin.port, daemonPort: WebContainer.shared.port),
           !frame.securityOrigin.host.isEmpty {
            alert.informativeText = "From \(frame.securityOrigin.host)"
        }
        return alert
    }

    // MARK: File picker

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        let response: NSApplication.ModalResponse
        if let window = Self.visibleWindow(of: webView) {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.urls : nil
    }

    // MARK: Camera and microphone

    /// Only Claude Science's own pages may use them.
    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        let isDaemon = WebRoute.isDaemonOrigin(scheme: origin.protocol, host: origin.host, port: origin.port,
                                               daemonPort: WebContainer.shared.port)
        return isDaemon ? .grant : .deny
    }

    // MARK: Sheets

    /// A sheet on a window nobody can see would never be answered, and the
    /// page would wait for it forever. Bring the window forward first, and
    /// fall back to a modal alert when the web view has no window at all.
    private func present(_ alert: NSAlert, over webView: WKWebView) async -> NSApplication.ModalResponse {
        guard let window = Self.visibleWindow(of: webView) else { return alert.runModal() }
        return await alert.beginSheetModal(for: window)
    }

    private static func visibleWindow(of webView: WKWebView) -> NSWindow? {
        guard let window = webView.window else { return nil }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible { window.makeKeyAndOrderFront(nil) }
        return window
    }
}
