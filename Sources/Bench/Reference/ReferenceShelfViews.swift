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

/// A kind tile: the file's ending in capitals ("MD", "CSV"), as Since You
/// Left draws a file without a picture, small enough for a row. Ringed in ink
/// once the file is on the shelf.
struct ReferenceKindTile: View {
    let label: String
    var ringed = false

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Solanum.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 44, height: 34)
            .background(Solanum.page, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(ringed ? Solanum.ink : Solanum.hairline, lineWidth: ringed ? 2 : 1))
            .accessibilityHidden(true)
    }
}

/// A small spinner on a card that is being read: on a round white ground,
/// since the picture under it can be any colour.
struct OpeningSpinner: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Solanum.raised.opacity(0.9)))
            .overlay(Circle().strokeBorder(Solanum.hairline, lineWidth: 1))
            .accessibilityLabel("Opening")
    }
}

/// A card that opens when pressed: a click, or Space or Return while it has
/// the keyboard. It draws its own focus, a thin ink ring just outside the
/// card (the system's would be the accent colour), and reads as a button to
/// VoiceOver. The ink ring on the card itself stays the shelf's mark.
struct OpensOnPress: ViewModifier {
    let radius: CGFloat
    let label: String
    let open: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(.rect(cornerRadius: radius))
            .onTapGesture(perform: open)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.space, .return]) { _ in
                open()
                return .handled
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: radius + 3)
                        .strokeBorder(Solanum.ink.opacity(0.55), lineWidth: 1.5)
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
            .pointerStyle(.link)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: label, open)
    }
}

extension View {
    func opensOnPress(radius: CGFloat, label: String, open: @escaping () -> Void) -> some View {
        modifier(OpensOnPress(radius: radius, label: label, open: open))
    }
}

/// A file of another kind in the reply (a document, a table): a kind tile,
/// its name and kind, and the pill, on a small card; ringed in ink once it is
/// on the shelf. Pressing the row opens the file (Quick Look, or the window
/// for Markdown).
struct ReferenceFileRow: View {
    let file: HistoryFile
    let mark: ShelfMark
    /// The file is being read to open it.
    var opening = false
    var open: () -> Void = {}
    let add: () -> Void
    let show: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReferenceKindTile(label: ReferenceFileRules.tile(file))
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Solanum.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ReferenceFileRules.detail(file))
                    .font(.system(size: 11))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if opening {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("Opening")
            }
            ShelfPill(mark: mark, add: add, show: show)
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Solanum.raised)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(mark == .on ? Solanum.ink : Solanum.hairline, lineWidth: mark == .on ? 2 : 1))
        .opensOnPress(radius: 10, label: ReferenceFileRules.readsInWindow(file) ? "Open \(file.name)" : "Open \(file.name) in Quick Look",
                      open: open)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ResultFileRow.label(file.kind)), \(file.name)")
    }
}
