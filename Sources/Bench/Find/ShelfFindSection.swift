// ShelfFindSection.swift — "In your sessions · 14" (DESIGN.md, Find any figure):
// the Shelf window's second section, under the shelf's own matches. Quiet on
// purpose: a heading, then one row for each file, drawn as board 11 draws its
// cards, smaller: a picture on paper or the kind's glyph, the file's name, and
// "session title · project · date" under it, with Add to Shelf at the end and a
// ⋯ menu that has all three things a match offers. Nothing here is clay: the
// Shelf window's one asking action is Show Where It Came From on its detail
// card, and this section asks for nothing until a pill is pressed.
import SwiftUI

struct ShelfFindSection: View {
    @ObservedObject var finder: ShelfFinder
    @ObservedObject var search: FindSearch
    @ObservedObject var thumbnails: ShelfThumbnails
    /// What the section says when nothing was found.
    let nothingMatches: String

    init(finder: ShelfFinder, nothingMatches: String = "Nothing in your sessions matches.") {
        self.finder = finder
        self.search = finder.search
        self.thumbnails = finder.thumbnails
        self.nothingMatches = nothingMatches
    }

    @State private var selected: String?

    var body: some View {
        let rows = finder.visible
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.bottom, 6)
            if rows.isEmpty {
                message
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.version) { index, file in
                        if index > 0 { Solanum.hairline.frame(height: 1) }
                        FindFileRow(file: file, mark: finder.mark(of: file), problem: finder.problems[file.version],
                                    thumbnails: thumbnails, isSelected: selected == file.version, isAvailable: finder.actions.isAvailable,
                                    select: { selected = file.version },
                                    add: { finder.add(file) },
                                    showWhere: { finder.showWhere(file) },
                                    results: { finder.openInResults(file) },
                                    showOnShelf: { finder.showOnShelf(file) })
                            .task(id: file.version) { await finder.wantPicture(of: file) }
                    }
                }
                // What was found for the words before these, until the answer lands.
                .opacity(search.isSearching ? 0.55 : 1)
            }
        }
        .padding(.horizontal, ShelfRules.gutter)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("In your sessions")
    }

    private var heading: some View {
        HStack(spacing: 8) {
            Text(finder.visible.isEmpty ? "In your sessions" : "In your sessions \u{00B7} \(finder.countText)")
                .font(.system(size: Solanum.captionSize, weight: .semibold))
                .foregroundStyle(Solanum.muted)
            if search.isSearching {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("Looking through your sessions")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var message: some View {
        if search.isSearching {
            Text("Looking\u{2026}")
                .font(.system(size: 13))
                .foregroundStyle(Solanum.muted)
                .padding(.vertical, 10)
        } else if search.couldntRead {
            Text("Capsid couldn\u{2019}t look through your sessions just now. Claude Science may be busy.")
                .font(.system(size: 13))
                .foregroundStyle(Solanum.muted)
                .padding(.vertical, 10)
        } else {
            Text(nothingMatches)
                .font(.system(size: 13))
                .foregroundStyle(Solanum.muted)
                .padding(.vertical, 10)
        }
    }
}

// MARK: One file

/// A found file: its picture on paper (or its kind's glyph), its name, where
/// it came from, and what can be done with it.
struct FindFileRow: View {
    let file: FoundFile
    let mark: ShelfMark
    let problem: String?
    @ObservedObject var thumbnails: ShelfThumbnails
    let isSelected: Bool
    let isAvailable: Bool
    let select: () -> Void
    let add: () -> Void
    let showWhere: () -> Void
    let results: () -> Void
    let showOnShelf: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            tile
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Solanum.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.caption())
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(1)
                if let problem {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .accessibilityHidden(true)
                        Text(problem)
                            .lineLimit(2)
                    }
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.ink)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            ShelfPill(mark: mark, add: add, show: showOnShelf)
                .disabled(!isAvailable)
            Menu {
                Button("Show Where It Came From", action: showWhere)
                Button("Open in Results", action: results)
                Divider()
                Button(ShelfWords.add, action: add)
                    .disabled(mark != .off)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(SolanumRoundStyle())
            .fixedSize()
            .disabled(!isAvailable)
            .accessibilityLabel("More for \(file.name)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isSelected ? Solanum.selection : .clear, in: .rect(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            select()
            showWhere()
        }
        .onTapGesture(perform: select)
        .contextMenu {
            Button("Show Where It Came From", action: showWhere)
            Button("Open in Results", action: results)
            Divider()
            Button(ShelfWords.add, action: add)
                .disabled(mark != .off)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(file.name), \(file.caption())")
        .accessibilityAction(named: "Show Where It Came From", showWhere)
        .accessibilityAction(named: "Open in Results", results)
        .accessibilityAction(named: ShelfWords.add, add)
    }

    /// A picture on paper, inset from its tile, as the cards have them; the
    /// kind's glyph until it comes, and for everything that isn't a picture.
    private var tile: some View {
        ZStack {
            Color.white
            if file.kind == .figure, let image = thumbnails.image(for: file.version) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                Image(systemName: ShelfPaper.symbol(file.kind))
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color(nsColor: .systemGray))
            }
        }
        .frame(width: 56, height: 42)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Solanum.hairline, lineWidth: 1))
    }
}

// MARK: When the shelf has nothing to show

/// The Shelf window's page while the search matches nothing on the shelf (or
/// the shelf is empty): one line saying so, with Clear Search, and the section.
struct ShelfFindPage: View {
    @ObservedObject var model: ShelfModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let line = shelfLine {
                    HStack(spacing: 12) {
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(Solanum.muted)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Button("Clear Search") { model.search = "" }
                            .buttonStyle(SolanumPillStyle(.small))
                    }
                    .padding(.horizontal, ShelfRules.gutter)
                    .padding(.top, 18)
                }
                ShelfFindSection(finder: model.finder)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// What the shelf's own search found, said once; none for an empty shelf.
    private var shelfLine: String? {
        guard !model.isEmpty else { return nil }
        let typed = model.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if let kind = model.kind, !model.scoped.isEmpty {
            return "No \(kind.noun) on your shelf match \u{201C}\(typed)\u{201D}."
        }
        return "Nothing on your shelf matches \u{201C}\(typed)\u{201D}."
    }
}
