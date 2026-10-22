// BrowserView.swift — the main window's content: the web view, the find bar
// when shown, and a quiet state while the daemon starts or if it can't.
import SwiftUI
import WebKit

struct BrowserView: View {
    @ObservedObject private var web = WebContainer.shared
    /// The Keep sheet for a file picked in the conversation (Shelf/ConversationMenu.swift).
    @ObservedObject private var sheets = ShelfSheetHost.shared
    @State private var width: CGFloat = KeepSheet.width

    var body: some View {
        // The web view never moves in this tree: everything else is an overlay
        // on it, so SwiftUI has no reason to rebuild it.
        WebViewHost(webView: web.webView)
            .overlay(alignment: .top) {
                FindOverlay(finder: web.finder)
            }
            .overlay {
                StatusOverlay(status: web.status, retriesOnItsOwn: web.retriesOnItsOwn, retry: web.start)
            }
            // The toast after Add to Shelf (Shelf/ShelfToast.swift).
            .overlay { ShelfToastHost() }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .sheet(item: $sheets.keeping) { model in
                KeepSheet(model: model, dismiss: { sheets.keeping = nil }, width: min(KeepSheet.width, max(360, width - 40)))
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
    let retry: () -> Void

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
                Button("Try again", action: retry)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.clay)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
    }
}
