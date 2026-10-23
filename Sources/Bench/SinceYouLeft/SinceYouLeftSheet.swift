// SinceYouLeftSheet.swift — the sheet that comes up when someone is back after
// 30 minutes or more away, drawn as board 2 of the Capsid 1.0 mock-ups
// (DESIGN.md, Since You Left): an ivory sheet with the time away and what
// changed in one sentence, how much of the 5-hour limit the stretch used, then
// what needs you (the question, its choices as radios, Send), what finished
// (Claude's last words and a few of its files) and what stopped (and why), and
// a foot with the one setting, Open Results and Done.
//
// Everything the sheet does with a session goes through what the panel's cards
// already do: the replier for a question (`QuestionReplier`, by `CardActions`),
// `LabModel.open`, the Results window and the Keep sheet. It reads nothing
// itself; the model's lazy reads fill the rows in (`loadDetails`).
import AppKit
import SwiftUI

// MARK: Pills and bars

/// Done: a slate-filled pill (ink on the page, so ivory on slate in the dark
/// appearance), semibold. One per view; `SolanumPillStyle` keeps clay for the
/// action that asks.
struct SolanumSlatePillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Solanum.page)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Capsule().fill(Solanum.ink))
            .overlay(Capsule().fill(Solanum.page).opacity(configuration.isPressed ? 0.18 : 0))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

/// The usage block's bar: 6 points, a track of the ink at 12% and a clay fill.
private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Solanum.ink.opacity(0.12))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Theme.clay).frame(width: proxy.size.width * min(1, max(0, fraction)))
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: Files as tiles

/// One small square under a finished row: the picture of an image, or a tile
/// naming the kind of file ("CSV", "MD", "XLSX").
enum SinceTile: Equatable, Sendable {
    case picture(version: String)
    case kind(String)

    /// Up to three: the images first (their pictures), then the rest as tiles.
    static let limit = 3

    @MainActor
    static func tiles(from entries: [ArtifactEntry], limit: Int = SinceTile.limit) -> [SinceTile] {
        let pictures = FinishedResults.pictures(in: entries).map { SinceTile.picture(version: $0.version) }
        let others = entries.filter { ArtifactGate.thumb(kind: $0.kind) != nil }.map { SinceTile.kind(label(for: $0)) }
        return Array((pictures + others).prefix(limit))
    }

    /// The file's own ending, in capitals, or its kind.
    static func label(for entry: ArtifactEntry) -> String {
        let ext = (entry.name as NSString).pathExtension.uppercased()
        if !ext.isEmpty, ext.count <= 5 { return ext }
        switch entry.kind {
        case .image: return "IMG"
        case .svg: return "SVG"
        case .markdown: return "MD"
        case .text: return "TXT"
        case .table: return "CSV"
        case .html: return "HTML"
        case .pdf: return "PDF"
        case .notebook: return "IPYNB"
        case .other: return "FILE"
        }
    }
}

private struct TileView: View {
    let tile: SinceTile
    @ObservedObject var store: ShelfThumbnails

    var body: some View {
        ZStack {
            switch tile {
            case .picture(let version):
                if let image = store.image(for: version) {
                    // Filled, as the board draws a figure: its own ground to the tile's edge.
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.system(size: 14, weight: .light)).foregroundStyle(PanelColor.slate.opacity(0.28))
                }
            case .kind(let label):
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Solanum.muted)
            }
        }
        .frame(width: 64, height: 48)
        .background(isPicture ? PanelColor.ivory : Solanum.raised, in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Solanum.hairline, lineWidth: 1))
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var isPicture: Bool {
        if case .picture = tile { true } else { false }
    }
}

// MARK: The sheet

struct SinceYouLeftSheet: View {
    static let width: CGFloat = 760

    @ObservedObject var model: SinceYouLeftModel
    @ObservedObject private var lab: LabModel
    @ObservedObject private var finished: FinishedResults
    /// Read so the buttons follow what the cards have read (the plan's, the question's).
    @ObservedObject private var plans: PlanApprover
    @ObservedObject private var questions: QuestionReplier
    /// The limit moves under the block.
    @ObservedObject private var usage = PlanUsageModel.shared
    @AppStorage(SinceYouLeftSettings.sheetKey) private var showsWhenAway = true
    /// "Show plans, questions and requests on the card", which the rows follow (the model reads it): kept here so the
    /// sheet draws again when it is turned off, or on, while the sheet is up. The model's reads are what act on it.
    @AppStorage(SettingsKey.showPlansOnCard) private var contentOn = true
    /// The shelf a finished row's figure is added to, and asked about.
    @ObservedObject var onShelf: ShelfAccess = .live
    /// Why the last Add to Shelf of a figure failed, by version, when it did.
    @State private var shelfProblems: [String: String] = [:]
    /// How tall the rows are, and the header and the foot: the scroll view is exactly as tall as its rows
    /// up to what `cap` leaves, so the window that follows the sheet's size shows them (a scroll view
    /// alone asks for no height) and scrolls only past it.
    @State private var rowsHeight: CGFloat = 0
    @State private var chromeHeights: [CGFloat] = [0, 0]
    @Environment(\.colorScheme) private var colorScheme

    /// Done and Esc, and the sheet's other ways out (Open, Results), by the controller.
    var done: () -> Void = {}
    var dismiss: () -> Void = {}
    /// The tallest the sheet grows before its body scrolls.
    var maxHeight: CGFloat?
    /// A card's actions over its own lab, for tests and demos.
    var cardActions: CardActions?

    init(model: SinceYouLeftModel, done: @escaping () -> Void = {}, dismiss: @escaping () -> Void = {},
         maxHeight: CGFloat? = nil, cardActions: CardActions? = nil) {
        self.model = model
        self.done = done
        self.dismiss = dismiss
        self.maxHeight = maxHeight
        let actions = cardActions ?? CardActions(model: model.lab, plans: .shared, questions: .shared)
        self.cardActions = actions
        _lab = ObservedObject(wrappedValue: model.lab)
        _finished = ObservedObject(wrappedValue: model.finished)
        _plans = ObservedObject(wrappedValue: actions.plans)
        _questions = ObservedObject(wrappedValue: actions.questions)
    }

    private var actions: CardActions { cardActions ?? CardActions(model: lab, plans: plans, questions: questions) }
    private var cap: CGFloat { maxHeight ?? min(720, (NSScreen.main?.visibleFrame.height ?? 900) - 120) }

    var body: some View {
        let summary = model.display
        let _ = contentOn
        VStack(spacing: 0) {
            header(summary)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeights[0] = $0 }
            hairline
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let summary {
                        sections(summary)
                    } else {
                        Text("Nothing is left to look at. Done closes this.")
                            .font(.system(size: 13))
                            .foregroundStyle(Solanum.muted)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .frame(height: min(rowsHeight, max(120, cap - chromeHeights.reduce(2, +))))
            .scrollBounceBehavior(.basedOnSize)
            hairline
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeights[1] = $0 }
        }
        .frame(width: Self.width)
        .background(Solanum.page)
        .presentationBackground(Solanum.page)
        // Esc: the same as Done, as Quick Open's sheet closes on it (the window's own `cancelOperation` is the fallback).
        .onExitCommand { done() }
        // The failure card's own reasons, and each ask's question, are read as the sheet comes up.
        .onAppear { model.loadDetails(cardActions: actions) }
        .onChange(of: model.display?.count) { _, _ in model.loadDetails(cardActions: actions) }
        // Turned back on: the rows that were not read are read now. (Turned off, the rows draw without what was read.)
        .onChange(of: contentOn) { _, _ in model.loadDetails(cardActions: actions) }
        .environment(\.appearsActive, true)
    }

    private var hairline: some View {
        Rectangle().fill(Solanum.hairline).frame(height: 1)
    }

    // MARK: Header

    private func header(_ summary: SinceYouLeftSummary?) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: SinceYouLeftText.overline(summary?.away(now: Date()) ?? model.awayDuration ?? 0))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Solanum.muted)
                Text(verbatim: summary?.headline ?? "Nothing changed")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Solanum.ink)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let used = model.usage() {
                usageBlock(used)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private func usageBlock(_ used: UsageWhileAway) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("5-hour limit used while away")
                    .foregroundStyle(Solanum.muted)
                Spacer(minLength: 8)
                Text(verbatim: "\(used.used)%")
                    .fontWeight(.semibold)
                    .foregroundStyle(Solanum.ink)
            }
            .font(.system(size: 12))
            UsageBar(fraction: Double(used.used) / 100)
            Text(verbatim: used.leftLine)
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
        }
        .frame(width: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("5-hour limit: \(used.used)% used while away. \(used.leftLine)")
    }

    // MARK: Sections

    @ViewBuilder
    private func sections(_ summary: SinceYouLeftSummary) -> some View {
        let shown = summary.shown()
        ForEach(shown.needs) { askCard($0) }
        if !shown.finished.isEmpty {
            sectionLabel("Finished")
            ForEach(Array(shown.finished.enumerated()), id: \.element.id) { index, row in
                if index > 0 { hairline }
                finishedRow(row)
            }
        }
        if !shown.stopped.isEmpty {
            sectionLabel("Stopped")
            ForEach(Array(shown.stopped.enumerated()), id: \.element.id) { index, row in
                if index > 0 { hairline }
                stoppedRow(row)
            }
        }
        if shown.hidden > 0 {
            Text(verbatim: "and \(shown.hidden) more. The activity list has them under Recent.")
                .font(.system(size: 12))
                .foregroundStyle(Solanum.muted)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Solanum.muted)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Needs you

    private func askCard(_ row: SinceYouLeftSummary.Row) -> some View {
        let session = row.session
        let reason = session.waitingReason ?? .other
        let offer = actions.offer(for: session)
        let ask = singleChoice(for: session)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: reason.sentence)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.clayText)
                TimelineView(.everyMinute) { context in
                    Text(verbatim: SinceYouLeftText.waiting(context.date.timeIntervalSince(row.at)))
                        .font(.system(size: 12))
                        .foregroundStyle(Solanum.muted)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: session.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Solanum.ink)
                    .lineLimit(2)
                Text(verbatim: session.projectName)
                    .font(.system(size: 12))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(1)
            }
            if let text = askText(for: session) {
                Text(verbatim: text)
                    .font(.system(size: Solanum.bodySize))
                    .lineSpacing(20 - 16.7)
                    .foregroundStyle(Solanum.ink)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ask {
                choices(ask, sessionID: session.id)
            }
            if let problem = offer.problem {
                Text(verbatim: problem)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.clayText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            askButtons(session, offer: offer, ask: ask)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Solanum.raised, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Solanum.strong, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    /// What the session asks, in words: its question, its plan's summary, what
    /// it wants permission for. Nil until the card's read has it.
    private func askText(for session: SessionStatus) -> String? {
        switch plans.state(for: session.id) {
        case .ready(let preview)?, .approving(let preview)?, .checking(let preview)?, .approved(let preview)?,
             .problem(_, let preview)?, .retry(_, let preview)?:
            return preview.summary
        default: break
        }
        switch questions.cardState(for: session.id) {
        case .ready(let ask)?: return ask.items.first?.question
        case .permission(let request)?: return RemotePermission.words(for: request).title
        case .loading?: return nil
        default: return nil
        }
    }

    /// The one question with options to choose from, when that is what it asks:
    /// radios are for it. Several questions, a choice of several, or none to
    /// choose from are answered in the reply window.
    private func singleChoice(for session: SessionStatus) -> QuestionAsk? {
        guard case .ready(let ask)? = questions.cardState(for: session.id), ask.items.count == 1,
              let item = ask.items.first, !item.multi, !item.options.isEmpty else { return nil }
        return ask
    }

    @ViewBuilder
    private func choices(_ ask: QuestionAsk, sessionID: String) -> some View {
        let item = ask.items[0]
        let picked = questions.replies[sessionID]?.draft.picks[0]?.first
        let selection = Binding<Int?>(get: { picked }, set: { new in
            guard let new else { return }
            questions.beginReply(sessionID)
            questions.updateDraft(sessionID) { $0.pick(new, in: 0, multi: false) }
        })
        Picker(item.header.isEmpty ? "Choices" : item.header, selection: selection) {
            ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                Text(verbatim: option.label).tag(Optional(index))
            }
        }
        .pickerStyle(.radioGroup)
        .horizontalRadioGroupLayout()
        .labelsHidden()
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func askButtons(_ session: SessionStatus, offer: CardOffer, ask: QuestionAsk?) -> some View {
        switch offer.lead {
        case .sending(let label):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).accessibilityLabel(label)
                openButton(session)
            }
        case .done(let text):
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(text)
                    Image(systemName: "checkmark")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.clayText)
                .accessibilityElement(children: .combine)
            }
        case .button(let lead):
            HStack(spacing: 8) {
                if ask != nil, lead == .reply {
                    // Send: the picked choice, by the card's own replier.
                    let ready = questions.replies[session.id].map { _ in questions.canSend(session.id) } ?? false
                    Button("Send") { send(session) }
                        .buttonStyle(SolanumPillStyle(.medium, prominent: true))
                        .disabled(!ready)
                        .help(CardAction.reply.help ?? "")
                    Button("Type an answer\u{2026}") { perform(.reply, for: session) }
                        .buttonStyle(SolanumPillStyle(.medium))
                    openButton(session)
                } else {
                    switch lead {
                    case .open, .openInCapsid:
                        Button(lead.title) { open(session) }
                            .buttonStyle(SolanumPillStyle(.medium, prominent: true))
                    default:
                        Button(lead.rowTitle) { perform(lead, for: session) }
                            .buttonStyle(SolanumPillStyle(.medium, prominent: true))
                            .help(lead.help ?? "")
                        if offer.hasOpen { openButton(session) }
                    }
                    if offer.hasDeny {
                        Button(CardAction.deny.title) { perform(.deny, for: session) }
                            .buttonStyle(SolanumPillStyle(.medium))
                    }
                    if offer.canRequestChanges {
                        Button(CardAction.requestChanges.title) { perform(.requestChanges, for: session) }
                            .buttonStyle(SolanumPillStyle(.medium))
                    }
                }
            }
        }
    }

    private func openButton(_ session: SessionStatus) -> some View {
        Button("Open") { open(session) }
            .buttonStyle(SolanumPillStyle(.medium))
    }

    /// Send: the draft the radios made, through the replier (it reads the
    /// session afresh and checks it still asks this question before it sends).
    private func send(_ session: SessionStatus) {
        questions.submit(session.id)
    }

    private func perform(_ action: CardAction, for session: SessionStatus) {
        if action.opensWindow { dismiss() }
        actions.perform(action, for: session)
    }

    private func open(_ session: SessionStatus) {
        dismiss()
        lab.open(session)
    }

    // MARK: Finished

    private func finishedRow(_ row: SinceYouLeftSummary.Row) -> some View {
        let session = row.session
        // The model's own gate: with the content setting off a row has no files, read before or not.
        let listing = model.listing(for: session.id)
        var tiles: [SinceTile] = []
        var keepable: ArtifactEntry?
        var hasFiles = false
        if case .loaded(let entries) = listing {
            tiles = SinceTile.tiles(from: entries)
            keepable = FinishedOffer.of(listing).keepable
            hasFiles = !entries.isEmpty
        }
        return FinishedRow(
            session: session, at: row.at, answer: model.detail(for: session.id)?.answer, tiles: tiles, store: finished.thumbnails,
            open: { open(session) }, results: hasFiles ? { showResults(session) } : nil,
            keep: keepable.map { entry in { keep(entry, of: session) } },
            shelf: keepable.map { ShelfMark($0.version, in: onShelf) },
            addToShelf: keepable.map { entry in { addToShelf(entry, of: session) } },
            showShelf: { onShelf.show(nil) },
            problem: keepable.flatMap { shelfProblems[$0.version] })
    }

    /// Add to Shelf, one click as in Results: the pill turns to "On Shelf ✓" from the shelf itself; a
    /// failure is a sentence under the row.
    private func addToShelf(_ entry: ArtifactEntry, of session: SessionStatus) {
        guard Demo.mode == nil, ShelfMark(entry.version, in: onShelf) == .off else { return }
        shelfProblems[entry.version] = nil
        Task { @MainActor in
            if case .failed(let sentence) = await onShelf.add(ShelfSource(session: session, entry: entry)) {
                shelfProblems[entry.version] = sentence
            }
        }
    }

    private func showResults(_ session: SessionStatus) {
        dismiss()
        guard Demo.mode == nil else { return }
        ResultsWindowController.shared.show(focusing: session)
    }

    private func keep(_ entry: ArtifactEntry, of session: SessionStatus) {
        guard Demo.mode == nil else { return }
        KeepFromCardController.shared.show(KeepSubject(session: session, entry: entry))
    }

    // MARK: Stopped

    private func stoppedRow(_ row: SinceYouLeftSummary.Row) -> some View {
        let session = row.session
        let reason = model.detail(for: session.id)?.reason
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Solanum.ink)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: session.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Solanum.ink)
                        .lineLimit(1)
                    Text(verbatim: SinceYouLeftText.meta(project: session.projectName, at: row.at))
                        .font(.system(size: 12))
                        .foregroundStyle(Solanum.muted)
                        .lineLimit(1)
                }
                if let reason {
                    Text(verbatim: reason)
                        .font(.system(size: 13))
                        .lineSpacing(19 - 15.5)
                        .foregroundStyle(Theme.clayText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let reason {
                Button("Copy") { copy(session.id, line: reason) }
                    .buttonStyle(SolanumPillStyle(.medium))
            }
            Button("Open") { open(session) }
                .buttonStyle(SolanumPillStyle(.medium))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(["Stopped with an error", session.displayTitle, session.projectName, reason].compactMap { $0 }.joined(separator: ". "))
    }

    private func copy(_ id: String, line: String) {
        // All of the reason when the card read it, else the line.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.fullReason(for: id) ?? line, forType: .string)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $showsWhenAway) {
                Text("Show this when I\u{2019}ve been away 30 minutes or more")
                    .font(.system(size: 12))
                    .foregroundStyle(Solanum.muted)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Results") {
                dismiss()
                if Demo.mode == nil { ResultsWindowController.shared.show() }
            }
            .buttonStyle(SolanumPillStyle(.regular))
            Button("Done") { done() }
                .buttonStyle(SolanumSlatePillStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }
}

// MARK: A finished row

/// A finished session: its title and when, the first two lines of Claude's
/// last answer, and up to three of its files as small tiles. A click opens the
/// session; with the pointer over it (or the keyboard on it) the row offers
/// Open, Results and, when exactly one figure was made, Add to Shelf (Keep with
/// Data and Code… in its menu), which are also
/// its context menu and VoiceOver's actions.
private struct FinishedRow: View {
    let session: SessionStatus
    let at: Date
    let answer: String?
    let tiles: [SinceTile]
    @ObservedObject var store: ShelfThumbnails
    let open: () -> Void
    let results: (() -> Void)?
    let keep: (() -> Void)?
    /// Where its figure stands on the shelf, when it has one to add.
    var shelf: ShelfMark? = nil
    var addToShelf: (() -> Void)? = nil
    var showShelf: () -> Void = {}
    /// Why the last add failed.
    var problem: String? = nil
    @State private var hovering = false
    /// Where the keyboard is on the row: the row itself or one of its pills. The pills are shown while any of
    /// them has the focus, not only the row, so Tab can get from one to the next (as on the activity list's rows).
    @FocusState private var focus: Focus?

    enum Focus: Hashable {
        case row
        case pill(String)
    }

    /// The pills are there while the pointer or the keyboard is on the row or on any of them.
    private var showsPills: Bool { hovering || focus != nil }

    private var tilesWidth: CGFloat { tiles.isEmpty ? 0 : CGFloat(tiles.count) * 64 + CGFloat(tiles.count - 1) * 6 + 16 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: session.displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Solanum.ink)
                                .lineLimit(1)
                            Text(verbatim: SinceYouLeftText.meta(project: session.projectName, at: at))
                                .font(.system(size: 12))
                                .foregroundStyle(Solanum.muted)
                                .lineLimit(1)
                        }
                        if let answer {
                            Text(verbatim: answer)
                                .font(.system(size: 13))
                                .lineSpacing(19 - 15.5)
                                .foregroundStyle(Solanum.muted)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let problem {
                            Text(verbatim: problem)
                                .font(.system(size: 12))
                                .foregroundStyle(Solanum.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                            TileView(tile: tile, store: store)
                        }
                    }
                }
                .padding(8)
                .background(showsPills ? Solanum.selection : .clear, in: .rect(cornerRadius: 8))
                .padding(-8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focused($focus, equals: .row)
            .accessibilityLabel([session.displayTitle, session.projectName, answer].compactMap { $0 }.joined(separator: ". "))
            .accessibilityHint("Opens the session")
            if showsPills {
                HStack(spacing: 6) {
                    Button("Open", action: open)
                        .focused($focus, equals: .pill("open"))
                    if let results {
                        Button("Results", action: results)
                            .focused($focus, equals: .pill("results"))
                    }
                    shelfPill
                }
                .buttonStyle(SolanumPillStyle(.small))
                .padding(.trailing, tilesWidth)
                .padding(.top, -2)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open", action: open)
            if let results { Button("Results", action: results) }
            shelfMenuItem
            if let keep { Button(ShelfWords.keep, action: keep) }
        }
        .accessibilityActions {
            if let results { Button("Results", action: results) }
            shelfMenuItem
            if let keep { Button(ShelfWords.keep, action: keep) }
        }
    }

    /// Add to Shelf, a spinner's "Adding…" while it is added, then "On Shelf ✓", which shows the shelf.
    @ViewBuilder private var shelfPill: some View {
        switch shelf {
        case .off?:
            if let addToShelf {
                Button(ShelfWords.add, action: addToShelf)
                    .focused($focus, equals: .pill("shelf"))
                    .help("Add to Shelf: this figure, with what Claude said about it and where it came from")
            }
        case .adding?:
            Button(ShelfWords.adding) {}.disabled(true)
        case .on?:
            Button(ShelfWords.on, action: showShelf)
                .focused($focus, equals: .pill("shelf"))
                .help("Show the Shelf")
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private var shelfMenuItem: some View {
        switch shelf {
        case .off?: if let addToShelf { Button(ShelfWords.add, action: addToShelf) }
        case .on?: Button("Show in Shelf", action: showShelf)
        case .adding?, nil: EmptyView()
        }
    }
}

// MARK: Hosting it as a sheet

/// The sheet window the main window carries. A sheet of the window it belongs
/// to, so it is the main window's own, not a floating one: Done and Esc end it.
@MainActor
final class SinceYouLeftSheetController: NSObject {
    static let shared: SinceYouLeftSheetController = SinceYouLeftSheetController()

    private var sheet: NSWindow?

    /// The window follows the sheet's ideal size: its rows, up to the screen's height.
    static let sizing: NSHostingSizingOptions = [.minSize, .maxSize]

    var isShowing: Bool { sheet != nil }

    /// Opens the sheet on the main window, bringing the window forward first.
    func show(model: SinceYouLeftModel = .shared) {
        guard sheet == nil else { return }
        Router.shared.showWindow()
        guard let parent = MainWindowController.shared.windowIfLoaded else { return }
        let view = SinceYouLeftSheet(model: model, done: { model.done() }, dismiss: { [weak self] in self?.close() })
        let host = NSHostingController(rootView: view)
        host.sizingOptions = Self.sizing
        let window = SheetWindow(contentViewController: host)
        window.styleMask = [.titled]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = Solanum.pageColor
        window.onCancel = { model.done() }
        sheet = window
        parent.beginSheet(window) { [weak self] _ in
            self?.sheet = nil
            model.sheetClosed()
        }
    }

    /// Takes the sheet down without clearing the summary.
    func close() {
        guard let window = sheet else { return }
        window.sheetParent?.endSheet(window)
        window.orderOut(nil)
        sheet = nil
    }
}

/// A sheet window that sends Esc to its owner.
private final class SheetWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
