// AskStreamSelectionTests.swift — a reader's selection while an answer streams in
// (Reference/ReferenceWindow.swift, `ReferenceTextView.keepsSelection`): the text is put in
// again every tenth of a second, and a selection made in it stays where it was when the new
// text reaches it; for a text that is not a stream's, a new text starts unselected as it
// always did. Drawn offscreen in a hosting view; no window opens.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
private final class Words: ObservableObject {
    @Published var text: NSAttributedString
    init(_ text: String) { self.text = NSAttributedString(string: text) }
}

private struct Probe: View {
    @ObservedObject var words: Words
    let keeps: Bool

    var body: some View {
        ReferenceTextView(text: words.text, selection: ReferenceSelection(), keepsSelection: keeps)
            .frame(width: 300)
    }
}

@MainActor
struct AskStreamSelectionTests {
    private func textView(in view: NSView) -> NSTextView? {
        if let found = view as? NSTextView { return found }
        for child in view.subviews { if let found = textView(in: child) { return found } }
        return nil
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<4 {
            try? await Task.sleep(for: .milliseconds(30))
            host.layoutSubtreeIfNeeded()
        }
    }

    /// Selects three characters, puts a longer text in, and says what is selected after.
    private func selection(keeps: Bool, longer: String) async throws -> NSRange {
        let words = Words("Use HEPES at 25 mM")
        let host = NSHostingView(rootView: Probe(words: words, keeps: keeps))
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        host.layoutSubtreeIfNeeded()
        await settle(host)
        let view = try #require(textView(in: host))
        view.setSelectedRange(NSRange(location: 4, length: 5))
        words.text = NSAttributedString(string: longer)
        await settle(host)
        return view.selectedRange()
    }

    @Test func aSelectionStaysWhileTheTextGrows() async throws {
        let range = try await selection(keeps: true, longer: "Use HEPES at 25 mM, because Tris drifts as the plate warms.")
        #expect(range == NSRange(location: 4, length: 5))
    }

    @Test func aSelectionTheNewTextDoesNotReachIsDropped() async throws {
        let range = try await selection(keeps: true, longer: "Use")
        #expect(range == NSRange(location: 0, length: 0))
    }

    @Test func aNewTextStartsUnselectedWhereTheViewDoesNotKeepOne() async throws {
        let range = try await selection(keeps: false, longer: "Use HEPES at 25 mM, because Tris drifts as the plate warms.")
        #expect(range == NSRange(location: 0, length: 0))
    }
}
