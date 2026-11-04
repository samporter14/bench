// PhoneReviewFixesTests.swift — the phone app's Markdown reader and table viewer after the
// 4 November phone review: a document is shown whole (the server's 256 KiB cap is the limit, and it
// says so), a list's preview still stops at 20,000 and never inside a surrogate pair, and a table
// has a way to read a clipped value. Made-up text in the phone app's own script, in JavaScriptCore.
import Foundation
import Testing
@testable import Bench

struct PhoneReviewFixesTests {
    private static let now = Date(timeIntervalSince1970: 1_791_986_400)

    private func app() throws -> PhoneAppHarness {
        try PhoneAppHarness(hash: "#/", now: Self.now, answers: [:])
    }

    /// The text of what `md(...)` built, as one string.
    private let flat = "(nodes) => nodes.map((n) => n.textContent).join('')"

    @Test func aDocumentOfTwentyThreeThousandCharactersIsShownToItsLastLine() throws {
        let app = try app()
        app.evaluate("var __doc = ('Paragraph about buffers. '.repeat(40) + '\\n\\n').repeat(22) + '## Final section\\n\\nTAIL-MARKER-END';")
        #expect(app.string("__doc.length > 20000 ? 'long' : 'short'") == "long")
        let whole = app.string("(\(flat))(md(__doc, { limit: Infinity })).includes('TAIL-MARKER-END')")
        #expect(whole == "true")
        let heading = app.string("(\(flat))(md(__doc, { limit: Infinity })).includes('Final section')")
        #expect(heading == "true")
    }

    @Test func aMessagePreviewStillStopsAtTwentyThousand() throws {
        let app = try app()
        app.evaluate("var __doc = ('word '.repeat(5000) + 'x'.repeat(3000)) + ' TAIL-MARKER-END';")
        #expect(app.string("(\(flat))(md(__doc)).includes('TAIL-MARKER-END')") == "false")
    }

    @Test func aCutNeverFallsBetweenTheHalvesOfAnEmoji() throws {
        let app = try app()
        // 19,999 letters, then a two-unit emoji: the cut at 20,000 would keep only its first half.
        app.evaluate("var __doc = 'a'.repeat(19999) + '\\u{1F600}' + 'tail';".replacingOccurrences(of: "\\u{1F600}", with: "\\uD83D\\uDE00"))
        #expect(app.string("(\(flat))(md(__doc)).length") == "19999")
        #expect(app.string("(\(flat))(md(__doc, { limit: Infinity })).length") == "20005")
    }

    @Test func aTableOffersToWrapItsCells() throws {
        let app = try app()
        app.evaluate("var __nodes = tableViewer({ columns: ['a', 'b'], rows: [['r1', 'x'.repeat(300)]], truncated: false });")
        #expect(app.string("__nodes.map((n) => n && n.textContent).join('|').includes('Wrap cells') ? 'yes' : 'no'") == "yes")
    }
}
