// ShelfDocumentCard.swift — documents read at the same scale as notes and Reference (since 1.0.7).
import SwiftUI

/// The file and its source, once. Drag and Quick Look stay on the header when the paper thumbnail goes away.
struct ShelfDocumentHeader: View {
    let item: ShelfItem
    let quickLook: KeptQuickLook

    var body: some View {
        Text(attributed)
            .font(.system(size: Solanum.captionSize))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .onDrag { ShelfActions.fileProvider(for: item) }
            .onTapGesture(count: 2) { quickLook.show([item.fileURL], at: 0) }
            .help("Drag the file into your manuscript, or double-click to preview it")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ShelfRules.documentHeaderParts(for: item).joined(separator: ", "))
    }

    private var attributed: AttributedString {
        let parts = ShelfRules.documentHeaderParts(for: item)
        var name = AttributedString(item.fileName)
        name.swiftUI.foregroundColor = Solanum.ink
        name.swiftUI.font = .system(size: Solanum.captionSize, weight: .medium)
        var rest = AttributedString(parts.dropFirst().map { ShelfRules.noteHeaderSeparator + $0 }.joined())
        rest.swiftUI.foregroundColor = Solanum.muted
        return name + rest
    }
}

/// The existing read-only Reference text view, within the note card's bounded reading area and bottom fade.
struct ShelfDocumentText: View {
    let document: AnswerDocument
    let fileName: String
    let maxHeight: CGFloat
    @State private var selection = ReferenceSelection()
    @State private var contentHeight: CGFloat = 40
    @State private var below: CGFloat = 0

    var body: some View {
        ScrollView {
            ReferenceTextView(text: document.text, selection: selection, accessibilityLabel: "Contents of \(fileName)")
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) {
            max(0, min(1, ($0.contentSize.height - $0.contentOffset.y - $0.containerSize.height) / ShelfPassageText.fade))
        } action: { _, now in below = now }
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(1 - below)], startPoint: .top, endPoint: .bottom)
                    .frame(height: ShelfPassageText.fade)
            }
        }
        .frame(height: min(contentHeight, maxHeight))
        .frame(maxWidth: ShelfPassageText.measure, alignment: .leading)
    }
}
