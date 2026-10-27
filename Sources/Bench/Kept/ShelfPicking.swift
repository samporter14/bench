// ShelfPicking.swift — choosing several things on the Shelf (DESIGN.md, Shelf →
// Lab-meeting PDF): the round pick circle at a card's corner (on the card under
// the pointer, and on every card once two are picked) adds it or takes it away
// with a plain click, as in Photos; ⌘-click does the same, ⇧-click takes the
// run from the last one clicked, ⌘A takes all that are shown, and a plain
// click, an arrow key or Esc goes back to one. The selected item (the one the
// detail card shows, and the arrows move from) is always among the picks, so
// everything the Shelf did with one selection works as it did. What is picked
// is what Export as PDF… makes: one page each, in the order the cards are shown.
// The rules are an extension of `ShelfModel`; the pieces that draw them
// (the toolbar's Export pill, shown once two or more are picked, the ⌘P that
// works with one too, the card that stands in for the detail while several are
// picked, with Compare on it for two that pair, the pick circle and page numbers
// on the cards) are here too, so ShelfView only places them.
import AppKit
import SwiftUI

extension ShelfModel {
    /// How a click picks.
    enum Pick: Equatable {
        /// This one alone: the plain click.
        case only
        /// Added, or taken away when it is picked: ⌘.
        case toggle
        /// The run from the last one clicked to this one: ⇧.
        case range

        init(_ flags: NSEvent.ModifierFlags) {
            if flags.contains(.shift) {
                self = .range
            } else if flags.contains(.command) {
                self = .toggle
            } else {
                self = .only
            }
        }
    }

    // MARK: What is picked

    /// The picked items, in the order the cards are shown.
    var pickedItems: [ShelfItem] { shown.filter { picked.contains($0.id) } }
    var pickCount: Int { picked.count }
    func isPicked(_ id: String) -> Bool { picked.contains(id) }
    /// The title bar's Export as PDF… pill: only once two or more are picked (board 12). With one, the card's menu, the
    /// detail's ⋯ and ⌘P export it.
    var showsExportPill: Bool { pickCount > 1 }

    /// A card's page in the PDF, 1 for the first: only while several are picked.
    func pageNumber(of id: String) -> Int? {
        guard picked.count > 1, picked.contains(id) else { return nil }
        let ids = shown.map(\.id).filter { picked.contains($0) }
        return ids.firstIndex(of: id).map { $0 + 1 }
    }

    // MARK: The pick circle

    /// What a card's top-left corner shows: nothing, an open hairline circle to pick it with, or its page number (it is
    /// picked, among several).
    enum PickCircle: Equatable {
        case hidden
        case open
        case number(Int)
    }

    /// The circle on card `id`. Once two or more are picked, every card has one (its number, or open), so the next is
    /// one plain click. With one, only the card under the pointer does, and never the selected card, which is picked
    /// already (its ink edge says so): its circle could only do nothing.
    func pickCircle(for id: String) -> PickCircle {
        if let page = pageNumber(of: id) { return .number(page) }
        if pickCount > 1 { return .open }
        return hoveredCard == id && selection != id && shown.contains { $0.id == id } ? .open : .hidden
    }

    /// Whether the card can be picked or unpicked from its circle (shown or not, as VoiceOver's action): every card but
    /// the selected one while it is the only pick.
    func offersPick(_ id: String) -> Bool {
        shown.contains { $0.id == id } && (pickCount > 1 || selection != id)
    }

    /// The circle's words, as a button and as the card's VoiceOver action.
    func pickCircleName(for id: String) -> String {
        pageNumber(of: id) == nil ? "Pick" : "Unpick"
    }

    /// The circle clicked (or its VoiceOver action): the card added to the picks, or taken away, as ⌘-click does.
    func pickCircleClicked(_ id: String) {
        pick(id, .toggle)
    }

    // MARK: Picking

    /// A click on card `id`, the way its modifiers say.
    func pick(_ id: String, _ how: Pick) {
        let ids = shown.map(\.id)
        guard ids.contains(id) else { return }
        switch how {
        case .only:
            selection = id
        case .toggle:
            if picked.contains(id) {
                // The last pick stays: the detail card and the arrows need something.
                guard picked.count > 1 else { return }
                var rest = picked
                rest.remove(id)
                let focus = selection == id ? (ids.first { rest.contains($0) } ?? id) : (selection ?? id)
                selection = focus
                picked = rest
            } else {
                let all = picked.union([id])
                selection = id
                picked = all
            }
        case .range:
            let anchor = pickAnchor.flatMap { ids.contains($0) ? $0 : nil } ?? selection ?? id
            guard let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: id) else {
                selection = id
                return
            }
            let run = Set(ids[min(from, to)...max(from, to)])
            selection = id
            picked = run
            pickAnchor = anchor
        }
    }

    /// ⌘A: everything shown, the selected card staying the one the detail shows.
    func pickAll() {
        let ids = shown.map(\.id)
        guard let first = ids.first else { return }
        let focus = selection.flatMap { ids.contains($0) ? $0 : nil } ?? first
        selection = focus
        picked = Set(ids)
        pickAnchor = first
    }

    /// Back to the selected card alone.
    func pickOnlySelected() {
        guard picked.count > 1, let selection else { return }
        self.selection = selection
    }

    // MARK: Export as PDF…

    /// Export Figure as PDF… (or "Export 3 Figures as PDF…") on what is picked. The task is the command's, for a test to wait for.
    ///
    /// The pages are decided after the save panel is answered, from the README of each picked item as it is then
    /// (`latest(of:)`): a legend typed in the last second, or one saved while the panel was up, is in the PDF.
    @discardableResult
    func exportPDF() -> Task<Void, Never> {
        let items = pickedItems
        guard !items.isEmpty else { return Task {} }
        return Task { [weak self] in
            guard let self else { return }
            await pdf.make(items, latest: { [weak self] in await self?.latest(of: $0) ?? $0 },
                           tell: { [weak self] in self?.say($0) })
        }
    }

    /// The card menu's name for the command: "Export 3 Figures as PDF…" on a card among the picks, which is what it
    /// exports, else "Export Figure as PDF…", the card alone.
    func exportName(from item: ShelfItem) -> String {
        let (count, allFigures) = exporting(from: item)
        return ShelfPDFRules.exportName(count: count, allFigures: allFigures)
    }

    /// The same, as VoiceOver offers it.
    func exportSpoken(from item: ShelfItem) -> String {
        let (count, allFigures) = exporting(from: item)
        return ShelfPDFRules.exportSpoken(count: count, allFigures: allFigures)
    }

    /// How many a card's Export as PDF… would export (the picks when the card is one, else the card), and whether
    /// they are all figures, so that a note or a document isn't called a figure.
    private func exporting(from item: ShelfItem) -> (count: Int, allFigures: Bool) {
        guard picked.contains(item.id) else { return (1, item.kind == .figure) }
        return (picked.count, items.filter { picked.contains($0.id) }.allSatisfy { $0.kind == .figure })
    }

    /// Export as PDF… from a card's menu: on the picks when that card is one of them, else on that card alone.
    @discardableResult
    func exportPDF(from item: ShelfItem) -> Task<Void, Never> {
        if !picked.contains(item.id) { pick(item.id, .only) }
        return exportPDF()
    }
}

// MARK: - The pieces

/// "Export as PDF…" in the title bar, once two or more are picked: a quiet pill (the one that asks is on the picked
/// card). The count is not in it (`ShelfPDFRules.exportPillName` says why); VoiceOver and the card say it. ⌘P is
/// `ShelfExportPDFKey`'s, so it works with one pick too, when the pill isn't there.
struct ShelfExportPDFButton: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var maker: ShelfPDFMaker

    init(model: ShelfModel) {
        self.model = model
        self.maker = model.pdf
    }

    private var label: String {
        if case .making(let done, let total) = maker.phase { return ShelfPDFRules.exporting(done: done, total: total) }
        return ShelfPDFRules.exportPillName
    }

    var body: some View {
        Button { model.exportPDF() } label: { Text(label) }
            .buttonStyle(SolanumPillStyle(.small))
            .disabled(maker.isMaking)
            .fixedSize()
            .help("\(ShelfPDFRules.exportSpoken(count: model.pickCount)). One figure on each page, 16:9, for lab meeting. \u{2318}P")
            .accessibilityLabel(ShelfPDFRules.exportSpoken(count: model.pickCount))
    }
}

/// ⌘P: Export as PDF… on what is picked, one card or several, whether or not the pill is in the title bar. A button
/// nobody sees (no size, no opacity, not hit, not read by VoiceOver: the pill, the card's menu and the detail's ⋯ are
/// the ways to it that are), so the key needs nothing on screen; the pill has no key of its own, so ⌘P never asks twice.
struct ShelfExportPDFKey: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var maker: ShelfPDFMaker

    init(model: ShelfModel) {
        self.model = model
        self.maker = model.pdf
    }

    var body: some View {
        Button(ShelfPDFRules.exportName(count: model.pickCount)) { model.exportPDF() }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(maker.isMaking || model.pickCount == 0)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Keys of picking on the grid: ⌘A takes everything shown, Esc goes back to one.
extension View {
    func shelfPickingKeys(_ model: ShelfModel) -> some View {
        self
            .onKeyPress(characters: CharacterSet(charactersIn: "aA"), phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                model.pickAll()
                return .handled
            }
            .onKeyPress(.escape) {
                guard model.pickCount > 1 else { return .ignored }
                model.pickOnlySelected()
                return .handled
            }
            // The Edit menu's Select All reaches the grid the same way.
            .onCommand(#selector(NSResponder.selectAll(_:))) { model.pickAll() }
    }
}

/// A card's pick circle (`ShelfModel.pickCircle`): an open hairline circle on the raised ground, or the page badge
/// when picked; a click on either picks or unpicks the card, with no key held. Drawn over the card's top-left corner,
/// where the page badge always sat.
struct ShelfPickCircle: View {
    @ObservedObject var model: ShelfModel
    let id: String

    var body: some View {
        let circle = model.pickCircle(for: id)
        if circle != .hidden {
            Button { model.pickCircleClicked(id) } label: {
                switch circle {
                case .number(let page):
                    ShelfPageBadge(number: page)
                default:
                    Circle()
                        .fill(Solanum.raised)
                        .overlay(Circle().strokeBorder(Solanum.muted, lineWidth: 1))
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Circle().inset(by: -4))
            .help(model.pickCircleName(for: id))
            .accessibilityLabel(model.pickCircleName(for: id))
        }
    }
}

/// A card's page in the PDF: a small ink disc with the number in the page's colour.
struct ShelfPageBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Solanum.page)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, number > 9 ? 3 : 0)
            .background(Capsule().fill(Solanum.ink))
            .accessibilityLabel("Page \(number)")
    }
}

/// In place of the detail while several are picked: how many, the pages in
/// order as small pictures, and the one action that asks (Export 3 Figures as PDF…, clay).
struct ShelfPickedCard: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var thumbnails: KeptThumbnails
    @ObservedObject var maker: ShelfPDFMaker

    init(model: ShelfModel, thumbnails: KeptThumbnails) {
        self.model = model
        self.thumbnails = thumbnails
        self.maker = model.pdf
    }

    /// As many small pictures as fit the least width the window has, then a count.
    private static let thumbnailsShown = 6

    /// "Export 3 Figures as PDF…", or "Exporting… 1/3" while it is made.
    private var exportTitle: String {
        if case .making(let done, let total) = maker.phase { return ShelfPDFRules.exporting(done: done, total: total) }
        return ShelfPDFRules.exportName(count: model.pickCount)
    }

    var body: some View {
        let items = model.pickedItems
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(items.count) selected")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Solanum.ink)
                    Text("One page each, in the order shown.")
                        .font(.system(size: Solanum.captionSize))
                        .foregroundStyle(Solanum.muted)
                }
                Spacer(minLength: 12)
                ShelfPickedActions(model: model, exportTitle: exportTitle, making: maker.isMaking)
            }
            HStack(spacing: 8) {
                ForEach(Array(items.prefix(Self.thumbnailsShown).enumerated()), id: \.element.id) { offset, item in
                    ShelfPickedThumb(item: item, thumbnails: thumbnails, page: offset + 1)
                }
                if items.count > Self.thumbnailsShown {
                    Text("+\(items.count - Self.thumbnailsShown)")
                        .font(.system(size: Solanum.captionSize))
                        .foregroundStyle(Solanum.muted)
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Solanum.raised, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ShelfLook.cardEdge, lineWidth: 1))
        .padding(.horizontal, ShelfRules.gutter)
        .padding(.bottom, ShelfLook.foot)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}

/// The picked card's row of actions: Clear, Compare for two that pair, and the one clay action, Export. Never cut
/// short: at the window's least width the caption beside them wraps instead (`CompareSnapshotTests` checks it fits).
struct ShelfPickedActions: View {
    @ObservedObject var model: ShelfModel
    let exportTitle: String
    let making: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button("Clear") { model.pickOnlySelected() }
                .buttonStyle(SolanumPillStyle(.medium))
                .help("Back to the one card")
            // Two that pair: Compare, quiet, beside the one clay action (CompareWindow.swift).
            ShelfCompareButton(model: model)
            Button(exportTitle) { model.exportPDF() }
                .buttonStyle(SolanumPillStyle(.medium, prominent: true))
                .disabled(making)
                .help("One figure on each page, 16:9, for lab meeting")
        }
        .fixedSize()
    }
}

/// A small picture of one page: the figure itself, or its kind's symbol (a note's lines
/// are too small to read at this size), with its number at the corner.
private struct ShelfPickedThumb: View {
    let item: ShelfItem
    @ObservedObject var thumbnails: KeptThumbnails
    let page: Int

    var body: some View {
        ZStack {
            if item.kind == .figure {
                ShelfPaper(store: thumbnails, url: item.fileURL, side: 140, kind: item.kind, inset: 3, symbolSize: 16)
            } else {
                Image(systemName: ShelfPaper.symbol(item.kind))
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Solanum.muted)
            }
        }
        .frame(width: 72, height: 50)
        .background(Solanum.raised, in: .rect(cornerRadius: 7))
        .clipShape(.rect(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Solanum.hairline, lineWidth: 1))
        .overlay(alignment: .topLeading) { ShelfPageBadge(number: page).offset(x: -5, y: -5) }
        .accessibilityHidden(true)
    }
}
