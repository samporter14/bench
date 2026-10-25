// ShelfClaudeLegendView.swift — the one quiet line in the detail card's legend area that offers Claude's own legend
// file (DESIGN.md, Shelf, "Claude's legend"; the rules and the work are in ShelfClaudeLegend.swift):
//
//     Use Claude's legend · FIGURE_LEGENDS_final.md
//
// With a legend already written it reads "Replace with Claude's legend…" and asks once before anything is replaced;
// with several files to choose from the name is a small menu, the best one first. No clay (the card's one clay action is
// Show Where It Came From): the words are the card's quiet links, muted and underlined, as More and Less are.
import SwiftUI

struct ShelfClaudeLegendLine: View {
    let item: ShelfItem
    @ObservedObject var model: ShelfModel
    @ObservedObject private var claude: ShelfClaudeLegend
    @ObservedObject private var editor: ShelfLegendEditor
    /// The file a written legend is about to be replaced with, while the question is on screen.
    @State private var asking: ShelfClaudeLegend.Candidate?

    init(item: ShelfItem, model: ShelfModel) {
        self.item = item
        self.model = model
        _claude = ObservedObject(wrappedValue: model.claudeLegend)
        _editor = ObservedObject(wrappedValue: model.legendEditor(for: item))
    }

    /// The legend as the card shows it: the field's once the README has been read, else the README's.
    private var legend: String { editor.canEdit ? editor.legend : item.text.legend }

    /// The field has something to settle first (a README changed in another app, a save that failed), or can't be read:
    /// its own lines say so, and this one waits.
    private var settling: Bool { editor.changedOutside || editor.problem != nil }

    private var offer: ShelfClaudeLegendRules.Offer? {
        settling ? nil : claude.offer(for: item, legend: legend)
    }

    var body: some View {
        if let offer, let best = offer.candidates.first {
            line(offer, best: best)
        }
    }

    private func line(_ offer: ShelfClaudeLegendRules.Offer, best: ShelfClaudeLegend.Candidate) -> some View {
        let busy = claude.busy.contains(item.id)
        return HStack(spacing: 6) {
            Button(offer.title) { choose(best, offer) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Solanum.muted)
                .underline()
                .disabled(busy)
                .accessibilityLabel("\(offer.title) from \(best.name)")
            Text("\u{00B7}")
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Solanum.muted)
                .accessibilityHidden(true)
            if offer.candidates.count > 1 {
                Menu {
                    ForEach(offer.candidates) { candidate in
                        Button(candidate.name) { choose(candidate, offer) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(best.name).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(ShelfQuietMenuStyle())
                .fixedSize()
                .disabled(busy)
                .accessibilityLabel("Choose another legend file")
                .help("Other files Claude made that look like a legend")
            } else {
                Text(best.name)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .confirmationDialog(ShelfClaudeLegendRules.replaceQuestion, isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { candidate in
            Button(ShelfClaudeLegendRules.replaceButton) { go(candidate, confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: { candidate in
            Text(ShelfClaudeLegendRules.replaceMessage(file: candidate.name))
        }
    }

    /// A written legend is asked about once; an empty one is filled at once.
    private func choose(_ candidate: ShelfClaudeLegend.Candidate, _ offer: ShelfClaudeLegendRules.Offer) {
        if offer.asksFirst { asking = candidate } else { go(candidate, confirmed: false) }
    }

    private func go(_ candidate: ShelfClaudeLegend.Candidate, confirmed: Bool) {
        let item = self.item
        Task { await model.useClaudeLegend(candidate, for: item, confirmed: confirmed) }
    }
}

/// The file's name as a menu: muted like the words beside it, a little lighter while pressed. (A borderless menu draws
/// its label in the system's colours and puts the arrows first.)
private struct ShelfQuietMenuStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Solanum.muted)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
