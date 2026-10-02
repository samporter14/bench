// Router.swift — the one place the Web and Lab halves meet. The web layer
// registers how to show the window and navigate its one web view; the lab
// layer asks to open a session or a notification. Neither imports the other.
import Foundation

/// A desktop notification Claude Science's page raised through the bridge
/// (DESIGN.md, Notification bridge).
struct WebNotification: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    /// Claude Science tags its notifications `operon-<root_frame_id>`.
    let tag: String?
    let requireInteraction: Bool
    let receivedAt: Date

    /// The session the notification is about, from its tag.
    var frameID: String? {
        guard let tag, tag.hasPrefix("operon-") else { return nil }
        return String(tag.dropFirst("operon-".count))
    }
}

@MainActor
final class Router {
    static let shared = Router()
    private init() {}

    // MARK: Registered by the web layer

    /// Shows the main window and brings Bench forward.
    var showWindow: () -> Void = {}
    /// Loads a daemon URL in the one web view.
    var navigate: (URL) -> Void = { _ in }
    /// Runs a page notification's click handler.
    var clickWebNotification: (String) -> Void = { _ in }

    // MARK: Registered by the lab layer

    /// A page notification arrived.
    var webNotificationArrived: (WebNotification) -> Void = { _ in }
    /// The page closed a notification it had shown (its id).
    var webNotificationClosed: (String) -> Void = { _ in }
    /// A download finished saving.
    var downloadSaved: (URL) -> Void = { _ in }

    // MARK: Called by anyone

    func open(_ url: URL) {
        showWindow()
        navigate(url)
    }

    func open(_ session: SessionStatus) {
        guard let url = session.deepLink else {
            showWindow()
            return
        }
        open(url)
    }

    func open(_ notification: WebNotification) {
        showWindow()
        clickWebNotification(notification.id)
    }

    /// `bench://open?url=…` and `bench://session?project=…&frame=…`.
    func handle(benchURL url: URL, port: Int?) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = parts.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch parts.host {
        case "open":
            if let text = value("url"), let target = URL(string: text) { open(target) } else { showWindow() }
        case "session":
            if let project = value("project"), let frame = value("frame"),
               let target = URL(string: "http://localhost:\(port ?? 8765)/projects/\(project)/frames/\(frame)") {
                open(target)
            } else {
                showWindow()
            }
        default:
            showWindow()
        }
    }
}
