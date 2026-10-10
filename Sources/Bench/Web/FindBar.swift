// FindBar.swift — ⌘F: find in the page (DESIGN.md, Find). A glass capsule at
// the top of the web view over WebKit's own find (PageFinder), in the main
// window and in each Browser, Preview and pop-up window.
import AppKit
import SwiftUI
import WebKit

/// The find bar at the top of a window's web view, while it is showing. A
/// view of its own, because it has to watch the finder: a window's model
/// holds the finder, and SwiftUI doesn't see inside it.
struct FindOverlay: View {
    @ObservedObject var finder: PageFinder

    var body: some View {
        if finder.isVisible {
            FindBar(finder: finder)
                .padding(.top, 10)
        }
    }
}

struct FindBar: View {
    @ObservedObject var finder: PageFinder
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
                .onExitCommand { finder.close() }
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
            Button { finder.close() } label: { Image(systemName: "xmark") }
                .help("Close")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        // After the bar is in the window: focus set during layout is dropped.
        .task { focused = true }
        .onChange(of: finder.request) { focused = true }
    }

    /// Only the newest search reports, so typing quickly can't leave the
    /// "No matches" note from an older one.
    private func find(backwards: Bool) {
        search?.cancel()
        let query = text
        search = Task {
            let found = await finder.find(query, backwards: backwards)
            guard !Task.isCancelled else { return }
            noMatch = !query.isEmpty && !found
        }
    }
}
