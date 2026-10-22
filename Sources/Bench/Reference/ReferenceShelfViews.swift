// ReferenceShelfViews.swift — what the reference window draws for the shelf
// (DESIGN.md, Reference and Shelf; board 11's right-hand window): the small
// pill under a figure or a file, "Add to Shelf", a spinner while it is added,
// "On Shelf ✓" once it is; the slate chip "✓ On your shelf" at the top left of
// a shelved figure; and the quiet row a file of another kind sits in. The
// mark of a shelved item is the chip and a 2-point ink ring, never the clay.
import SwiftUI

/// The pill: Add to Shelf, Adding…, On Shelf ✓. The last opens the shelf.
struct ShelfPill: View {
    let mark: ShelfMark
    let add: () -> Void
    let show: () -> Void

    var body: some View {
        switch mark {
        case .off:
            Button(ShelfWords.add, action: add)
                .buttonStyle(SolanumPillStyle(.small))
                .help("Put this on your shelf, with what Claude said about it and where it came from")
        case .adding:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(ShelfWords.adding)
            }
            .font(.system(size: Solanum.captionSize))
            .foregroundStyle(Solanum.muted)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Adding to your shelf")
        case .on:
            Button(ShelfWords.on, action: show)
                .buttonStyle(SolanumPillStyle(.small))
                .help("It is on your shelf. Show the shelf.")
        }
    }
}

/// "✓ On your shelf": ink on the card's top left, ivory words (slate on ivory
/// in the dark), 22 points high, after the board.
struct OnShelfChip: View {
    var body: some View {
        HStack(spacing: 5) {
            ShelfCheck()
                .stroke(Solanum.page, style: StrokeStyle(lineWidth: 1.25, lineCap: .butt, lineJoin: .miter))
                .frame(width: 10, height: 10)
            Text("On your shelf")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Solanum.page)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(Solanum.ink))
        .accessibilityElement(children: .combine)
    }
}

/// A file of another kind in the reply (a document, a table): its kind's
/// glyph, its name and kind, and the pill; ringed in ink once it is on the
/// shelf.
struct ReferenceFileRow: View {
    let file: HistoryFile
    let mark: ShelfMark
    let add: () -> Void
    let show: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ResultFileRow.symbol(file.kind))
                .font(.system(size: 14))
                .foregroundStyle(Solanum.muted)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Solanum.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ShelfPill(mark: mark, add: add, show: show)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Solanum.raised)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(mark == .on ? Solanum.ink : Solanum.hairline, lineWidth: mark == .on ? 2 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ResultFileRow.label(file.kind)), \(file.name)")
    }

    /// "Markdown · 4 KB".
    private var detail: String {
        [ResultFileRow.label(file.kind), file.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}
