// FindBar.swift — ⌘F: find in the page (DESIGN.md, Find). A glass capsule at
// the top of the web view over WebKit's own find, so highlighting, scrolling
// and counting are the system's.
import AppKit
import SwiftUI
import WebKit

extension WebContainer {
    /// Finds `text`, wrapping around, and reports whether it is on the page.
    /// An empty string clears the highlight.
    func find(_ text: String, backwards: Bool) async -> Bool {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        configuration.caseSensitive = false
        let result = try? await webView.find(text, configuration: configuration)
        return result?.matchFound ?? false
    }

    /// Closes the bar and gives the keyboard back to the page.
    func closeFind() {
        webView.find("") { _ in }
        isFindVisible = false
        webView.window?.makeFirstResponder(webView)
    }
}

struct FindBar: View {
    @ObservedObject var web: WebContainer
    @State private var text = ""
    @State private var noMatch = false
    @State private var search: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in page", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .focused($focused)
                // Return finds the next match, and Shift-Return the previous.
                .onSubmit { find(backwards: NSEvent.modifierFlags.contains(.shift)) }
                .onExitCommand { web.closeFind() }
                .onChange(of: text) { find(backwards: false) }
            if noMatch {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { find(backwards: true) } label: { Image(systemName: "chevron.up") }
                .help("Previous match")
            Button { find(backwards: false) } label: { Image(systemName: "chevron.down") }
                .help("Next match")
            Button { web.closeFind() } label: { Image(systemName: "xmark") }
                .help("Close")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        // After the bar is in the window: focus set during layout is dropped.
        .task { focused = true }
        .onChange(of: web.findRequest) { focused = true }
    }

    /// Only the newest search reports, so typing quickly can't leave the
    /// "No matches" note from an older one.
    private func find(backwards: Bool) {
        search?.cancel()
        let query = text
        search = Task {
            let found = await web.find(query, backwards: backwards)
            guard !Task.isCancelled else { return }
            noMatch = !query.isEmpty && !found
        }
    }
}
