// ShelfToolbarButton.swift — the "Shelf · 12" pill beside the Results button
// in the main window's toolbar (DESIGN.md, Shelf; board 10): the shelf glyph
// and the live count; a click opens the Shelf window (⇧⌘K). With nothing on the
// shelf it says just "Shelf". It sits on the toolbar's own glass, drawn like
// its neighbours (`ReadoutButtonStyle`), not as the board's white pill: the
// toolbar is the system's.
import SwiftUI

struct ShelfToolbarButton: View {
    @ObservedObject var shelf: ShelfAccess

    init(shelf: ShelfAccess = .live) {
        self.shelf = shelf
    }

    var body: some View {
        let count = shelf.count()
        Button { shelf.show(nil) } label: {
            HStack(spacing: 6) {
                ShelfGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .butt, lineJoin: .miter))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(ShelfWords.pill(count: count))
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
        }
        .buttonStyle(ReadoutButtonStyle())
        .help("The Shelf: figures and files you put aside, and where each came from (\u{21E7}\u{2318}K)")
        .accessibilityLabel(count > 0 ? "Shelf, \(count) \(count == 1 ? "item" : "items")" : "Shelf")
        .disabled(Demo.mode != nil)
        .onAppear { if Demo.mode == nil { shelf.prime() } }
    }
}
