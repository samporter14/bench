// ShelfView.swift — the Shelf window's content (DESIGN.md, Shelf), drawn as
// board 12 of the Capsid 1.0 mock-ups ("the same shelf, a little prettier"):
// the project pill by "Shelf" and the search at the right of the title bar,
// the kind chips (All, Figures, Documents, Tables, each with its count), the
// cards under quiet day headings (Today, Yesterday, This week…), three across
// at the window's first width, each a picture on paper filling its card and
// the file's name with its extension in grey, and at the foot the detail of
// the one selected: its picture, its name, the session, project, version and
// time, what you asked, what Claude said, and Show Where It Came From (clay),
// Copy and a ⋯ menu with the rest. An item kept with data and code also shows
// its legend and its files below. Hairlines, no shadows, 24-point gutters.
// The rules are in ShelfRules, the choices in ShelfModel; this file only draws.
import AppKit
import SwiftUI

/// Board 12's measures that aren't the Solanum kit's own.
enum ShelfLook {
    /// A card's edge: the hairline, softer (ink at 12% on ivory).
    static let cardEdge = Solanum.hairline.opacity(0.8)
    /// The detail card's edge, between the hairline and the strong edge (ink at 20%).
    static let detailEdge = Solanum.strong.opacity(0.67)
    /// An extension after a name: quieter than a caption.
    static let extensionInk = Solanum.muted.opacity(0.72)
    /// A card's picture: as wide as its column, this much less tall (board 12's 285 by 150).
    static let tileAspect: CGFloat = 285.0 / 150.0
    static let tileRadius: CGFloat = 12
    /// Room under the detail card, at the window's foot.
    static let foot: CGFloat = 22
}

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var index: KeptIndex
    @ObservedObject var thumbnails: KeptThumbnails
    let quickLook: KeptQuickLook
    @FocusState private var gridFocused: Bool
    @State private var keeping: KeepModel?
    @State private var size: CGSize = KeptWindowController.size

    init(model: ShelfModel, thumbnails: KeptThumbnails, quickLook: KeptQuickLook) {
        self.model = model
        self.index = model.index
        self.thumbnails = thumbnails
        self.quickLook = quickLook
    }

    var body: some View {
        content
            .frame(minWidth: 620, minHeight: 480)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            // ⌘P, with one card picked or several (ShelfPicking.swift).
            .background(alignment: .topLeading) { ShelfExportPDFKey(model: model) }
            .background {
                // The title bar's band under the transparent bar, the page below it.
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Solanum.bar
                            .frame(height: proxy.safeAreaInsets.top)
                            .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                        Solanum.page
                    }
                    .ignoresSafeArea()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 10) {
                        Text("Shelf")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Solanum.ink)
                        ShelfProjectPill(model: model)
                    }
                    .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
                // On the Mac, items start at the leading edge, and with the title removed nothing pushes them right:
                // board 12 has the search at the right of the bar (board 11's window drew it by the project pill).
                ToolbarSpacer(.flexible)
                if model.showsExportPill {
                    ToolbarItem {
                        ShelfExportPDFButton(model: model)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem {
                    ShelfSearchPill(search: $model.search, width: ShelfSearchPill.width(forWindow: size.width))
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .sheet(item: $keeping) { keep in
                KeepSheet(model: keep, dismiss: { keeping = nil }, width: max(360, min(KeepSheet.width, size.width)))
            }
            .onAppear { gridFocused = true }
    }

    // MARK: The page

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if model.isEmpty {
                // Nothing on the shelf, but a search worth a look in the sessions.
                if model.finder.isWanted { ShelfFindPage(model: model) } else { nothingOnTheShelf }
            } else {
                chips
                if let selected = model.selected {
                    grid
                    if model.pickCount > 1 {
                        ShelfPickedCard(model: model, thumbnails: thumbnails)
                    } else {
                        detail(selected)
                    }
                } else if model.finder.isWanted {
                    ShelfFindPage(model: model)
                } else {
                    empty
                }
            }
        }
    }

    // MARK: The chips

    private var chips: some View {
        let counts = model.counts
        return HStack(spacing: 8) {
            ForEach([ShelfKind?.none, .figure, .document, .table], id: \.self) { kind in
                Button(ShelfRules.chipLabel(kind, counts)) { model.kind = kind }
                    .buttonStyle(ShelfChipStyle(selected: model.kind == kind))
                    .accessibilityLabel("\(kind?.chip ?? "All"), \(counts.of(kind))")
                    .accessibilityAddTraits(model.kind == kind ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ShelfRules.gutter)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: The cards, under their days

    private var grid: some View {
        let count = ShelfRules.columns(forWidth: size.width)
        let columns = Array(repeating: GridItem(.flexible(), spacing: ShelfRules.gap, alignment: .top), count: count)
        let days = model.days
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { offset, day in
                            Text(model.title(of: day.day))
                                .font(.system(size: Solanum.captionSize, weight: .semibold))
                                .tracking(0.12)
                                .foregroundStyle(Solanum.muted)
                                .padding(.top, offset == 0 ? 6 : 22)
                                .padding(.bottom, 10)
                                .accessibilityAddTraits(.isHeader)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: ShelfRules.gap) {
                                ForEach(day.items) { item in
                                    card(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, ShelfRules.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    // Below the shelf's own matches: the same words, in every session.
                    if model.finder.isWanted {
                        ShelfFindSection(finder: model.finder, nothingMatches: "Nothing else in your sessions matches.")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: model.selection) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            // A window opened on an item further down (Show Shelf) starts with it in view, once the cards are laid out;
            // on the first, at the top.
            .task {
                guard let id = model.selection, id != model.shown.first?.id else { return }
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(id)
            }
        }
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { model.move(-1, 0); return .handled }
        .onKeyPress(.rightArrow) { model.move(1, 0); return .handled }
        .onKeyPress(.upArrow) { model.move(0, -1); return .handled }
        .onKeyPress(.downArrow) { model.move(0, 1); return .handled }
        .onKeyPress(.space) { previewSelected() ? .handled : .ignored }
        .shelfPickingKeys(model)
        .overlay(alignment: .bottom) {
            if let note = model.note {
                ShelfNote(note: note, undo: { model.undoNote() })
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.note)
        // ↑ and ↓ count in the rows drawn.
        .onAppear { model.columns = count }
        .onChange(of: count) { _, now in model.columns = now }
    }

    private func card(_ item: ShelfItem) -> some View {
        let isSelected = model.isPicked(item.id)
        // A search that found it only in its text says so, quietly, on its caption.
        let caption = ShelfRules.caption(for: item) + (model.foundOnlyInText(item) ? " \u{00B7} \(ShelfRules.inTextSentence)" : "")
        return VStack(alignment: .leading, spacing: 7) {
            // The picture fills its card, a few points in from the edge: on its paper, which is white in both appearances.
            Color.clear
                .aspectRatio(ShelfLook.tileAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    ShelfPaper(store: thumbnails, url: item.fileURL, side: item.kind == .figure ? 320 : 600, kind: item.kind, inset: 5,
                               symbolSize: 34, radius: 8, peekScale: 1.15, margin: item.kind == .figure ? 4 : 10)
                }
                .background(Solanum.raised, in: .rect(cornerRadius: ShelfLook.tileRadius))
                .overlay(RoundedRectangle(cornerRadius: ShelfLook.tileRadius)
                    .strokeBorder(isSelected ? Solanum.ink : ShelfLook.cardEdge, lineWidth: isSelected ? 2 : 1))
                .overlay(alignment: .topLeading) {
                    if let page = model.pageNumber(of: item.id) { ShelfPageBadge(number: page).offset(x: -5, y: -5) }
                }
                .accessibilityHidden(true)
            ShelfName(parts: item.nameParts, size: 13, weight: isSelected ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.selection = item.id
            quickLookSelected()
        }
        .onTapGesture {
            // ⌘ adds the card or takes it away, ⇧ picks the run from the last one.
            model.pick(item.id, ShelfModel.Pick(NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags))
            gridFocused = true
        }
        .id(item.id)
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
        .contextMenu {
            Button("Show Where It Came From") { ShelfActions.showWhereItCameFrom(item) }
                .disabled(Demo.mode != nil)
            Button("Quick Look") { model.selection = item.id; quickLookSelected() }
            Button("Copy") { ShelfActions.copy(item, disk: model.index.disk) }
            // On the picks when this card is one of them, else on this card alone: the name says which.
            Button(model.exportName(from: item)) { model.exportPDF(from: item) }
            Divider()
            Button("Open") { NSWorkspace.shared.open(item.fileURL) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.folder]) }
            Divider()
            Button("Remove") { model.selection = item.id; model.removeSelected() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(caption)" + (model.pageNumber(of: item.id).map { ", page \($0)" } ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selection = item.id }
    }

    // MARK: Nothing to show

    /// An empty shelf, or one that can't be read: said once, in the page's voice.
    @ViewBuilder
    private var nothingOnTheShelf: some View {
        switch index.state {
        case .idle, .reading:
            Color.clear
        case .rootMissing:
            KeptEmpty(title: "The Shelf folder isn\u{2019}t there",
                      sentence: "\(KeepRules.abbreviated(index.rootURL)) was moved or deleted, or its disk isn\u{2019}t connected.",
                      action: ("Choose Folder\u{2026}", { KeptFolderSection.chooseRoot { index.refresh() } }))
        case .failed(let sentence):
            KeptEmpty(title: "The Shelf folder didn\u{2019}t respond", sentence: sentence,
                      action: ("Try Again", { index.refresh() }))
        case .ready:
            KeptEmpty(title: ShelfRules.emptyTitle, sentence: ShelfRules.emptySentence, action: nil)
        }
    }

    /// Items on the shelf, none of them shown: the search or a chip is the reason.
    @ViewBuilder
    private var empty: some View {
        if !model.search.isEmpty, model.scoped.isEmpty {
            KeptEmpty(title: "Nothing on your shelf matches \u{201C}\(model.search)\u{201D}",
                      sentence: "Search covers names, sessions, legends and Claude\u{2019}s words.",
                      action: ("Clear Search", { model.search = "" }))
        } else if let kind = model.kind {
            KeptEmpty(title: ShelfRules.emptyKindTitle(kind), sentence: ShelfRules.emptyKindSentence(kind),
                      action: ("Show All", { model.kind = nil }))
        } else if let project = model.project {
            KeptEmpty(title: "Nothing from \(project) yet", sentence: "Choose another project, or all of them.",
                      action: ("All Projects", { model.project = nil }))
        } else {
            KeptEmpty(title: "Nothing selected", sentence: "Choose an item.", action: nil)
        }
    }

    // MARK: The detail

    private func detail(_ item: ShelfItem) -> some View {
        ShelfDetail(item: item, model: model, thumbnails: thumbnails, quickLook: quickLook,
                    keep: { keepWithDataAndCode(item) },
                    // A search that also looks in the sessions leaves them more of the window.
                    maxHeight: model.finder.isWanted ? max(220, size.height * 0.34) : max(220, size.height * 0.56),
                    previewWidth: ShelfDetail.previewWidth(forWindow: size.width))
    }

    private func keepWithDataAndCode(_ item: ShelfItem) {
        guard keeping == nil, let subject = ShelfActions.keepSubject(item) else { return }
        keeping = KeepModel(subject: subject, dependencies: .live(shelf: .shared))
    }

    // MARK: Quick Look

    private func previewSelected() -> Bool {
        guard model.selected != nil else { return false }
        quickLookSelected()
        return true
    }

    private func quickLookSelected() {
        let shown = model.shown
        guard let at = shown.firstIndex(where: { $0.id == model.selection }) else { return }
        quickLook.show(shown.map(\.fileURL), at: at)
    }
}

// MARK: The title bar's pills

/// The project shown, as a pill: "All projects" or one by name.
struct ShelfProjectPill: View {
    @ObservedObject var model: ShelfModel

    var body: some View {
        Menu {
            Button { model.project = nil } label: {
                if model.project == nil { Label("All projects", systemImage: "checkmark") } else { Text("All projects") }
            }
            if !model.projects.isEmpty { Divider() }
            ForEach(model.projects, id: \.self) { name in
                Button { model.project = name } label: {
                    if model.project == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.project ?? "All projects")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SolanumPillStyle(.small))
        .fixedSize()
        .accessibilityLabel("Project, \(model.project ?? "all projects")")
    }
}

/// Search, as a pill at the right of the title bar.
struct ShelfSearchPill: View {
    @Binding var search: String
    var width: CGFloat = 200

    /// Board 12's 200 points, and less in a narrow window, where the bar also holds "Shelf", the project pill and,
    /// with several picked, Export as PDF….
    static func width(forWindow width: CGFloat) -> CGFloat { width < 760 ? 160 : 200 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
                .accessibilityHidden(true)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Solanum.ink)
                .accessibilityLabel("Search the shelf")
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 26)
        .background(Capsule().fill(Solanum.raised))
        .overlay(Capsule().strokeBorder(Solanum.strong, lineWidth: 1))
    }
}

// MARK: Actions

/// What the buttons do, apart from the window.
@MainActor
enum ShelfActions {
    /// "Show Where It Came From": the reference reader at the message that showed it.
    static func showWhereItCameFrom(_ item: ShelfItem) {
        let record = item.record
        ReferenceWindowController.shared.show(sessionID: record.sessionID, projectID: record.projectID, title: record.sessionTitle,
                                              projectName: record.projectName, at: record.sourceRow, mark: record.figure.version)
    }

    /// The file on the pasteboard at once and, for a figure, the picture too, in the same item, when it has been
    /// read (`KeptDisk`, off the main actor) and made ready (`ShelfPicture`, on a thread of its own). Nothing is
    /// read or decoded on the main actor; the file may be on a share. The picture is added only if nothing else
    /// has been copied meanwhile. The task is the picture's, for a test to wait for.
    @discardableResult
    static func copy(_ item: ShelfItem, disk: KeptDisk, to pasteboard: NSPasteboard = .general) -> Task<Void, Never> {
        pasteboard.clearContents()
        pasteboard.writeObjects([item.fileURL as NSURL])
        let count = pasteboard.changeCount
        guard item.kind == .figure else { return Task {} }
        let url = item.fileURL
        return Task { @MainActor in
            guard let bytes = try? await disk.pictureBytes(url),
                  let picture = await ShelfPicture.flavor(of: bytes, fileName: url.lastPathComponent),
                  pasteboard.changeCount == count else { return }
            pasteboard.addTypes([picture.type], owner: nil)
            pasteboard.setData(picture.data, forType: picture.type)
        }
    }

    /// The Keep sheet's subject for an item: its version, pinned to the answer
    /// that was kept with it. Nil for a folder with no version to keep.
    static func keepSubject(_ item: ShelfItem) -> KeepSubject? {
        let record = item.record
        guard let version = record.figure.version else { return nil }
        let session = SessionStatus(id: record.sessionID, projectID: record.projectID, projectName: record.projectName,
                                    title: record.sessionTitle, state: .finished, updatedAt: record.keptAt, startedAt: nil)
        let entry = ArtifactEntry(version: version, artifact: record.figure.artifact, name: record.figure.path, mime: nil,
                                  size: record.figure.bytes, at: nil)
        let pinned = item.text.claudeSaid.isEmpty || ShelfRules.isLastAnswer(item.text)
            ? nil : KeepPinnedAnswer(text: item.text.claudeSaid, at: record.answerAt)
        // The shelf's own version stays the pick, even with no answer to pin it by.
        return KeepSubject(session: session, entry: entry, pinned: pinned, selectsItsVersion: true)
    }
}

// MARK: The detail card

/// The selected item at the window's foot: its picture, its name, where it came from in one line, what was asked,
/// what Claude said, and three controls: Show Where It Came From (the one that asks, clay), Copy, and ⋯ with Keep
/// with Data and Code…, Export Figure as PDF… and Remove. Each of the ⋯ items is also a VoiceOver action on the card.
struct ShelfDetail: View {
    let item: ShelfItem
    @ObservedObject var model: ShelfModel
    @ObservedObject var thumbnails: KeptThumbnails
    let quickLook: KeptQuickLook
    let keep: () -> Void
    let maxHeight: CGFloat
    var previewWidth: CGFloat = 250
    @State private var copied = false
    @State private var sayingMore = false
    /// The card's height as measured; a guess until then, so it never fills the window for a frame.
    @State private var contentHeight: CGFloat = 200

    private var said: String { item.text.claudeSaid.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var longSaid: Bool { said.count > 170 || said.filter(\.isNewline).count > 2 }
    private var more: [ShelfRules.MoreItem] { ShelfRules.moreMenu(canKeep: item.canKeepWithDataAndCode) }

    /// Board 12's 250 points, less in a narrow window so the three controls stay on one row beside it.
    static func previewWidth(forWindow width: CGFloat) -> CGFloat {
        min(250, max(160, ((width - 2 * ShelfRules.gutter - 36) * 0.3).rounded()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 22) {
                    preview
                    VStack(alignment: .leading, spacing: 6) {
                        ShelfName(parts: item.nameParts, size: 17, weight: .semibold)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Text(ShelfRules.sourceLine(for: item))
                            .font(.system(size: Solanum.captionSize))
                            .foregroundStyle(Solanum.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if let asked = ShelfRules.askedLine(for: item) {
                            Text(asked)
                                .font(.system(size: 13))
                                .lineSpacing(19 - 15.5)
                                .foregroundStyle(Solanum.muted)
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                        if !said.isEmpty {
                            Text(said)
                                .font(.system(size: 13))
                                .lineSpacing(19 - 15.5)
                                .foregroundStyle(Solanum.ink)
                                .lineLimit(sayingMore ? nil : 3)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if longSaid {
                                Button(sayingMore ? "Less" : "More") { sayingMore.toggle() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Solanum.muted)
                                    .underline()
                            }
                            if let note = ShelfRules.lastAnswerNote(for: item) {
                                Text(note)
                                    .font(.system(size: Solanum.captionSize))
                                    .foregroundStyle(Solanum.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        buttons
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                }
                if item.hasMore {
                    Solanum.hairline.frame(height: 1).padding(.top, 18)
                    ShelfExtras(item: item, model: model)
                        .id(item.id)
                        .padding(.top, 16)
                } else if model.claudeLegend.offer(for: item, legend: item.text.legend) != nil {
                    // A figure shelved alone has no legend field; Claude's own legend file, if the answer made one, is offered here.
                    Solanum.hairline.frame(height: 1).padding(.top, 18)
                    ShelfClaudeLegendLine(item: item, model: model)
                        .id(item.id)
                        .padding(.top, 14)
                }
            }
            .padding(18)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Claude's legend file for this figure, if its answer made one (ShelfClaudeLegend.swift).
        .task(id: item.id) { await model.claudeLegend.look(at: item) }
        .frame(height: min(contentHeight, maxHeight))
        .background(Solanum.raised, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ShelfLook.detailEdge, lineWidth: 1))
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            // What moved into ⋯, still a VoiceOver action away.
            ForEach(more.filter { $0 != .divider }, id: \.self) { entry in
                Button(entry.spoken) { perform(entry) }
            }
        }
        .padding(.horizontal, ShelfRules.gutter)
        .padding(.bottom, ShelfLook.foot)
        .padding(.top, 8)
        .onChange(of: item.id) { _, _ in
            sayingMore = false
            copied = false
        }
    }

    private var preview: some View {
        ShelfPaper(store: thumbnails, url: item.fileURL, side: item.kind == .figure ? 300 : 560, kind: item.kind, inset: 6, symbolSize: 40,
                   radius: 6, margin: item.kind == .figure ? 6 : 8)
            .frame(width: previewWidth, height: 150)
            .background(Solanum.raised, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ShelfLook.cardEdge, lineWidth: 1))
            .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
            .onTapGesture(count: 2) { quickLook.show([item.fileURL], at: 0) }
            .accessibilityLabel("Preview of \(item.fileName)")
            .help("Drag it into your manuscript, or double-click to preview it")
    }

    private var buttons: some View {
        ShelfFlow(spacing: 8) {
            Button {
                ShelfActions.showWhereItCameFrom(item)
            } label: {
                Text("Show Where It Came From")
            }
            .buttonStyle(SolanumPillStyle(.regular, prominent: true))
            .disabled(Demo.mode != nil)
            .help(item.record.sourceRow == nil
                  ? "The conversation it came from, in Capsid"
                  : "The conversation, at the message that showed it")
            Button(copied ? "Copied" : "Copy") {
                ShelfActions.copy(item, disk: model.index.disk)
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .buttonStyle(SolanumPillStyle(.regular))
            .help(item.kind == .figure ? "The file and its picture" : "The file")
            Menu {
                ForEach(Array(more.enumerated()), id: \.offset) { _, entry in
                    if entry == .divider {
                        Divider()
                    } else {
                        Button(entry == .exportPDF ? model.exportName(from: item) : entry.title) { perform(entry) }
                            .disabled(entry == .keepWithDataAndCode && Demo.mode != nil)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(ShelfMoreStyle())
            .fixedSize()
            .help("Keep with Data and Code, Export as PDF, Remove")
            .accessibilityLabel("More for \(item.fileName)")
        }
    }

    /// What a ⋯ item (or its VoiceOver action) does.
    private func perform(_ entry: ShelfRules.MoreItem) {
        switch entry {
        case .keepWithDataAndCode:
            guard Demo.mode == nil else { return }
            keep()
        case .exportPDF:
            model.exportPDF(from: item)
        case .remove:
            model.removeSelected()
        case .divider:
            break
        }
    }
}

/// The detail's ⋯: a round button the height of the pills beside it (30 points), white with a strong hairline.
private struct ShelfMoreStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Solanum.ink : Solanum.muted)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Solanum.raised))
            .overlay(Circle().fill(Solanum.hairline).opacity(configuration.isPressed ? 1 : 0))
            .overlay(Circle().strokeBorder(Solanum.strong, lineWidth: 1))
            .contentShape(Circle())
    }
}

/// A file's name with its extension in grey after it, or a keep's own name whole (`ShelfRules.nameParts`). The
/// extension is never bold, as board 12 draws it; VoiceOver reads the name whole.
struct ShelfName: View {
    let parts: ShelfRules.NameParts
    let size: CGFloat
    var weight: Font.Weight = .regular

    var body: some View {
        Text(attributed)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Solanum.ink)
            .accessibilityLabel(parts.whole)
    }

    private var attributed: AttributedString {
        var name = AttributedString(parts.name)
        guard !parts.ext.isEmpty else { return name }
        var ext = AttributedString(parts.ext)
        ext.swiftUI.foregroundColor = ShelfLook.extensionInk
        ext.swiftUI.font = .system(size: size, weight: .regular)
        name.append(ext)
        return name
    }
}

/// The legend and the files of an item kept with data and code: today's Kept
/// detail, under the card's main row.
struct ShelfExtras: View {
    let item: ShelfItem
    @ObservedObject var model: ShelfModel
    /// The legend field's text, its saves and its problem (ShelfLegend.swift). One per item, and the model's, not
    /// the card's: a draft whose save failed after the card was left is here when the item is chosen again.
    @ObservedObject private var editor: ShelfLegendEditor

    init(item: ShelfItem, model: ShelfModel) {
        self.item = item
        self.model = model
        _editor = ObservedObject(wrappedValue: model.legendEditor(for: item))
    }

    private var record: KeptRecord { item.record }
    /// The README couldn't be read: the field is off, and the line says why.
    private var unreadable: Bool { !editor.canEdit && editor.problem != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                label("Files")
                VStack(alignment: .leading, spacing: 4) {
                    fileRow(record.figure)
                    ForEach(record.files, id: \.path) { fileRow($0) }
                    ForEach(record.missing, id: \.name) { missing in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(missing.name).font(.system(size: 12)).foregroundStyle(Solanum.muted).lineLimit(1)
                            Text("Not copied: \(missing.reason)").font(.system(size: 11)).foregroundStyle(Solanum.muted)
                        }
                    }
                }
            }
            .frame(width: 260, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                label("Your legend")
                TextField("The legend you\u{2019}ll use in the paper", text: $editor.legend, axis: .vertical)
                    .lineLimit(2...8)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Solanum.ink)
                    .lineSpacing(3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Solanum.page, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Solanum.strong, lineWidth: 1))
                    .accessibilityLabel("Your legend")
                    .disabled(!editor.canEdit)
                    .opacity(unreadable ? 0.55 : 1)
                if let problem = editor.problem {
                    note(problem)
                }
                if editor.changedOutside {
                    HStack(spacing: 8) {
                        note("README.md was changed in another app.")
                        Button("Use Mine") { Task { await editor.useMine() } }
                        Button("Use Theirs") { Task { await editor.load() } }
                    }
                    .buttonStyle(SolanumPillStyle(.small))
                }
                ShelfClaudeLegendLine(item: item, model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A draft kept from before is shown as it was left; anything else is read from the README.
        .task { await editor.show() }
        // Another item chosen, or the window closed: what was typed in the last second is saved now, not dropped, and
        // if that save fails the draft stays with the model and the window says so.
        .onDisappear { editor.hide() }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Solanum.captionSize, weight: .semibold))
            .foregroundStyle(Solanum.muted)
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.clay).accessibilityHidden(true)
            Text(text).font(.system(size: 12)).foregroundStyle(Solanum.ink)
        }
    }

    private func fileRow(_ file: KeptFile) -> some View {
        let url = item.folder.appendingPathComponent(file.path)
        return HStack(spacing: 8) {
            Text(file.path)
                .font(.system(size: 12))
                .foregroundStyle(Solanum.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

// MARK: Pieces

/// A picture on paper: Quick Look's, a text file's first lines (`ShelfPeek`),
/// or the kind's symbol until it comes. The paper is white in both appearances
/// (a figure is drawn for it), inset from its card so the card's own ground
/// frames it in the dark; in the light the two are one white.
struct ShelfPaper: View {
    @ObservedObject var store: KeptThumbnails
    let url: URL
    let side: CGFloat
    let kind: ShelfKind
    let inset: CGFloat
    let symbolSize: CGFloat
    /// The paper's corners; a little less than the inset by default.
    var radius: CGFloat?
    /// How large a text file's first lines are drawn: 1 at the old card's size; by default more past an inset of 8.
    var peekScale: CGFloat?
    /// Room between the paper's edge and a picture, so a figure drawn to its own edges doesn't touch it.
    var margin: CGFloat = 0
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            Color.white
            if store.usesPeek(url) {
                // Drawn from the file's text; blank until it has been read.
                if let peek = store.peek(for: url) {
                    ShelfPeekView(peek: peek, scale: peekScale ?? (inset >= 8 ? 1.3 : 1))
                }
            } else if let image = store.image(for: url, side: side) {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFit()
                    .padding(margin)
            } else {
                Image(systemName: ShelfPaper.symbol(kind))
                    .font(.system(size: symbolSize, weight: .light))
                    .foregroundStyle(Color(nsColor: .systemGray))
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.rect(cornerRadius: radius ?? max(3, inset - 2)))
        .padding(inset)
        .onAppear { request() }
        // The detail card keeps its picture's view when the selection moves, so
        // the new file's picture is asked for here, not only when it appears.
        .onChange(of: url) { request() }
        // A file that wasn't text after all goes to Quick Look.
        .onChange(of: store.usesPeek(url)) { _, uses in
            if !uses { store.want(url, side: side, scale: scale, cropped: kind != .figure) }
        }
    }

    private func request() {
        if store.usesPeek(url) { store.wantPeek(url) } else { store.want(url, side: side, scale: scale, cropped: kind != .figure) }
    }

    static func symbol(_ kind: ShelfKind) -> String {
        switch kind {
        case .figure: "photo"
        case .document: "doc.text"
        case .table: "tablecells"
        }
    }
}

/// A text file's first lines on paper, as boards 11 and 12 draw a note: a bold
/// heading and small grey paragraphs; a table's first rows in a light grid.
/// The paper is white in both appearances, so the words are ink and grey
/// whatever the window's.
struct ShelfPeekView: View {
    let peek: ShelfPeek
    /// 1 on a card; more in the detail's larger picture.
    let scale: CGFloat

    private static let ink = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255)
    private static let muted = Color(red: 0x5E / 255, green: 0x5D / 255, blue: 0x59 / 255)

    var body: some View {
        content
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 8 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch peek {
        case .document(let title, let paragraphs):
            VStack(alignment: .leading, spacing: 6 * scale) {
                if let title {
                    Text(title)
                        .font(.system(size: 11 * scale, weight: .bold))
                        .foregroundStyle(Self.ink)
                        .lineLimit(2)
                }
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 9 * scale))
                        .lineSpacing(2.3 * scale)
                        .foregroundStyle(Self.muted)
                }
            }
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 8 * scale, verticalSpacing: 4 * scale) {
                ForEach(Array(rows.enumerated()), id: \.offset) { row, cells in
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.system(size: 8.5 * scale, weight: row == 0 ? .bold : .regular))
                                .foregroundStyle(row == 0 ? Self.ink : Self.muted)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if row == 0 {
                        Rectangle().fill(Self.ink.opacity(0.18)).frame(height: 1).gridCellColumns(max(cells.count, 1))
                    }
                }
            }
        case .lines(let lines):
            VStack(alignment: .leading, spacing: 2 * scale) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 8 * scale, design: .monospaced))
                        .foregroundStyle(Self.muted)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A kind chip: 28 points, white with a strong edge; selected, ink with the page's words.
struct ShelfChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(selected ? Solanum.page : Solanum.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Solanum.ink : Solanum.raised))
            .overlay(Capsule().fill(Solanum.hairline).opacity(configuration.isPressed && !selected ? 1 : 0))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Solanum.strong, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// The line after a removal: a dark glass pill, as the toast in the conversation is.
struct ShelfNote: View {
    let note: ShelfModel.Note
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(note.sentence)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xF5 / 255))
                .lineLimit(2)
            if note.hasUndo {
                Button("Undo", action: undo)
                    .buttonStyle(ShelfNoteButtonStyle())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, note.hasUndo ? 8 : 16)
        .frame(minHeight: 40)
        .background(Capsule().fill(Color(red: 28 / 255, green: 28 / 255, blue: 27 / 255).opacity(0.9)))
        .overlay(Capsule().strokeBorder(Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xF5 / 255).opacity(0.18), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}

private struct ShelfNoteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xF5 / 255))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0)))
            .overlay(Capsule().strokeBorder(Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xF5 / 255).opacity(0.32), lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Views in a row that wraps to the next when the width runs out.
struct ShelfFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, arranged.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}
