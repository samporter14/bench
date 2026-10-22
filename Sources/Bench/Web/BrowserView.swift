// BrowserView.swift — the main window's content: the web view, the find bar
// when shown, and a quiet state while the daemon starts or if it can't.
import SwiftUI
import WebKit

struct BrowserView: View {
    @ObservedObject private var web = WebContainer.shared

    var body: some View {
        // The web view never moves in this tree: everything else is an overlay
        // on it, so SwiftUI has no reason to rebuild it.
        WebViewHost(webView: web.webView)
            .overlay(alignment: .top) {
                FindOverlay(finder: web.finder)
            }
            .overlay {
                StatusOverlay(status: web.status, retriesOnItsOwn: web.retriesOnItsOwn, companion: web.companion,
                              retry: web.start, openScience: web.openScience)
            }
    }
}

/// Puts an existing web view into SwiftUI. It always returns the one it was
/// given, and never makes a new one.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Covers the web view while the daemon starts or after it failed. Opaque, so
/// the web view's blank page never shows through.
private struct StatusOverlay: View {
    let status: WebContainer.Status
    let retriesOnItsOwn: Bool
    /// Beside Claude Science's own app (Web/DaemonPolicy.swift): the button
    /// that asks is Open Claude Science, with Try again beside it.
    let companion: WebContainer.Companion
    let retry: () -> Void
    let openScience: () -> Void

    var body: some View {
        switch status {
        case .ready:
            EmptyView()
        case .starting:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting Claude Science…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        case .failed(let message):
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if retriesOnItsOwn {
                        Text("Capsid reconnects by itself as soon as Claude Science answers.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                if companion == .none {
                    Button("Try again", action: retry)
                        .buttonStyle(.glassProminent)
                        .tint(Theme.clay)
                } else {
                    HStack(spacing: 10) {
                        Button(CompanionSentence.openButton, action: openScience)
                            .buttonStyle(.glassProminent)
                            .tint(Theme.clay)
                        Button("Try again", action: retry)
                            .buttonStyle(.glass)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
    }
}
