// Routing.swift — where a link goes (DESIGN.md, Web routing policy). One pure
// function sorts a URL by origin, and one dispatcher sends it home, so the
// main view, the pop-ups and the Browser window can't drift apart.
import AppKit
import os

extension Logger {
    /// Everything in Web/ logs here.
    static let web = Logger(subsystem: "local.sam.bench", category: "web")
    /// The app's own: the Dock menu.
    static let app = Logger(subsystem: "local.sam.bench", category: "app")
}

/// What a URL is, judged against the daemon's port.
enum LinkTarget: Equatable, Sendable {
    /// Claude Science itself: `http://localhost:<port>` or `127.0.0.1`.
    case daemon
    /// A generated HTML preview: localhost or 127.0.0.1 on any other port.
    case preview
    /// Any other http(s) page.
    case web
    /// Blank pages and blob:, data: and javascript: content, which belong to
    /// whoever made them and only ever load in place.
    case inert
    /// mailto:, tel:, file: and other schemes: macOS deals with these.
    case external
}

enum WebRoute {
    /// The same test for a URL and for a `WKSecurityOrigin`.
    static func isDaemonOrigin(scheme: String?, host: String?, port: Int?, daemonPort: Int?) -> Bool {
        guard let daemonPort, scheme?.lowercased() == "http", isLoopback(host) else { return false }
        // WKSecurityOrigin reports a default port as 0.
        let effective = port.flatMap { $0 == 0 ? nil : $0 } ?? 80
        return effective == daemonPort
    }

    static func classify(_ url: URL?, daemonPort: Int?) -> LinkTarget {
        guard let url, let scheme = url.scheme?.lowercased() else { return .inert }
        switch scheme {
        case "about", "blob", "data", "javascript":
            return .inert
        case "http", "https":
            if isDaemonOrigin(scheme: scheme, host: url.host, port: url.port, daemonPort: daemonPort) { return .daemon }
            if scheme == "http", isLoopback(url.host) { return .preview }
            return .web
        default:
            return .external
        }
    }

    private static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1"
    }
}

/// Sends a link somewhere other than the web view it was clicked in.
@MainActor
enum LinkDispatcher {
    static func open(_ url: URL, as target: LinkTarget) {
        switch target {
        case .daemon:
            Router.shared.open(url)
        case .preview:
            WebWindows.shared.openPreview(url)
        case .web:
            WebWindows.shared.openBrowser(url)
        case .inert:
            break
        case .external:
            openExternally(url)
        }
    }

    /// A page link can't launch a local program: `file:` is shown in Finder
    /// rather than opened, and every other scheme goes to its handler.
    static func openExternally(_ url: URL) {
        if url.isFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
