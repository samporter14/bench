// ShelfOutOfDate.swift — what the Shelf window does with an item that is out of date (DESIGN.md, Shelf → Out of
// date): the mark on its card and its paper slot, the sentences on its detail, and the two ways on from there. The
// verdict is ShelfFreshness.swift's and the reading ShelfFreshnessCheck.swift's; this is the window's part.
//
// Keep the Newer One makes a new folder of the newest version and never touches the old one: an item kept with its
// data and code opens the Keep sheet on the newest version (Keep picks a name of its own, dated or numbered when the
// old one's is taken); an item only shelved is shelved again at the newest version, beside the old. Compare (kept vs
// newest) needs both on disk, so it is offered once the newest is on the shelf, and until then Keep the Newer One is.
import SwiftUI

extension ShelfModel {
    /// The verdict for `item`, from what has been read so far this window session.
    func freshness(of item: ShelfItem) -> ShelfFreshness { freshness.verdict(for: item) }

    /// The newest version of `item`'s figure, when Claude Science has a newer one than the one kept.
    func newerFigure(of item: ShelfItem) -> ArtifactVersion? {
        if case .stale(let stale) = freshness(of: item) { stale.newerFigure } else { nil }
    }

    /// The shelf's own item of the newest version, when it has been kept: what Compare puts beside the old one.
    func newestOnShelf(for item: ShelfItem) -> ShelfItem? {
        guard let newer = newerFigure(of: item) else { return nil }
        return items.first { $0.version == newer.v && $0.id != item.id }
    }

    /// How many of `items` are out of date, as far as is known.
    func outOfDate(_ items: [ShelfItem]) -> Int {
        ShelfFreshnessRules.countOutOfDate(items.map(freshness(of:)))
    }

    /// Keep the Newer One for an item only shelved: the newest version shelved beside the old one. A Keep sheet is
    /// the view's (`ShelfOutOfDate.newerSubject`).
    func shelveNewer(_ item: ShelfItem) {
        guard Demo.mode == nil, let newer = newerFigure(of: item) else { return }
        let source = ShelfSource(session: ShelfOutOfDate.session(of: item), entry: ShelfOutOfDate.entry(for: item, newer))
        Task { @MainActor in
            switch await shelf.add(source) {
            case .added(let placed):
                say("Kept the newer version as \u{201C}\(placed.name)\u{201D}. The one you kept before is as it was.")
                index.refresh()
            case .alreadyOnShelf:
                say("The newer version is on your shelf already.")
            case .failed(let sentence):
                say(sentence)
            }
        }
    }
}

enum ShelfOutOfDate {
    /// The session an item came from, as Keep and the shelf take it.
    static func session(of item: ShelfItem) -> SessionStatus {
        let record = item.record
        return SessionStatus(id: record.sessionID, projectID: record.projectID, projectName: record.projectName,
                             title: record.sessionTitle, state: .finished, updatedAt: record.keptAt, startedAt: nil)
    }

    /// The newest version as an artifact entry: the same artifact and name, its own version.
    static func entry(for item: ShelfItem, _ newer: ArtifactVersion) -> ArtifactEntry {
        ArtifactEntry(version: newer.v, artifact: item.record.figure.artifact, name: item.record.figure.path, mime: newer.mime,
                      size: newer.size, at: newer.at)
    }

    /// The Keep sheet's subject for the newest version of an item kept with its data and code. No answer is pinned:
    /// the one kept with the old version didn't make this one.
    static func newerSubject(_ item: ShelfItem, _ newer: ArtifactVersion) -> KeepSubject {
        KeepSubject(session: session(of: item), entry: entry(for: item, newer), pinned: nil, selectsItsVersion: true)
    }
}

/// The small mark on a card's picture and a paper's slot: "Out of date", or "Not in Claude Science". Clay is for
/// what needs you, and this does; nothing is drawn while nothing is known.
struct ShelfStaleMark: View {
    let freshness: ShelfFreshness

    var body: some View {
        if let label = ShelfFreshnessRules.shortLabel(freshness) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Solanum.slateInk)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(Solanum.clayFill))
                .help(freshness.sentences.joined(separator: " "))
                .accessibilityLabel(freshness.sentences.joined(separator: " "))
        }
    }
}

/// The detail's lines for an item out of date: what changed, and the way on (Keep the Newer One, or Compare with the
/// Newer One once it is on the shelf), as hairline pills; Show Where It Came From stays the card's one clay control.
struct ShelfStaleLines: View {
    let item: ShelfItem
    @ObservedObject var model: ShelfModel
    let keepNewer: () -> Void

    var body: some View {
        let verdict = model.freshness(of: item)
        if !verdict.sentences.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(verdict.sentences, id: \.self) { sentence in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(Solanum.clayFill).frame(width: 6, height: 6)
                        Text(sentence)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Solanum.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.newerFigure(of: item) != nil {
                    HStack(spacing: 8) {
                        if let newest = model.newestOnShelf(for: item) {
                            Button("Compare with the Newer One") { CompareWindowController.shared.show(item, newest) }
                                .buttonStyle(SolanumPillStyle(.regular))
                        } else {
                            Button("Keep the Newer One") { keepNewer() }
                                .buttonStyle(SolanumPillStyle(.regular))
                                .disabled(Demo.mode != nil)
                                .help("A new folder for the newest version; the one you kept stays as it is")
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.top, 4)
        }
    }
}
