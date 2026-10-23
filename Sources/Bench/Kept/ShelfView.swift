// ShelfView.swift — the Shelf window's content (DESIGN.md, Shelf), drawn as
// board 11 of the Capsid 1.0 mock-ups: a project pill and a search pill in the
// title bar, the kind chips (All, Figures, Documents, Tables, each with its
// count), a grid of four cards a row with Quick Look pictures, and at the foot
// the detail of the one selected: its picture, its name, where it came from,
// what you asked, what Claude said, and four pills, the one that asks in clay.
// An item kept with data and code also shows its legend and its files below.
// The rules are in ShelfRules, the choices in ShelfModel; this file only draws.
import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var index: KeptIndex
    @ObservedObject var thumbnails: KeptThumbnails
    let quickLook: KeptQuickLook
    @FocusState private var gridFocused: Bool
    @State private var keeping: KeepModel?
    @State private var size: CGSize = CGSize(width: 880, height: 820)

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
                ToolbarItem(placement: .primaryAction) {
                    ShelfSearchPill(search: $model.search)
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
                    detail(selected)
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
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    // MARK: The grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: ShelfModel.columns)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(model.shown) { item in
                            card(item)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
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
        }
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { model.move(-1, 0); return .handled }
        .onKeyPress(.rightArrow) { model.move(1, 0); return .handled }
        .onKeyPress(.upArrow) { model.move(0, -1); return .handled }
        .onKeyPress(.downArrow) { model.move(0, 1); return .handled }
        .onKeyPress(.space) { previewSelected() ? .handled : .ignored }
        .overlay(alignment: .bottom) {
            if let note = model.note {
                ShelfNote(note: note, undo: { model.undoRemoval() })
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.note)
    }

    private func card(_ item: ShelfItem) -> some View {
        let isSelected = item.id == model.selection
        return VStack(alignment: .leading, spacing: 6) {
            ShelfPaper(store: thumbnails, url: item.fileURL, side: item.kind == .figure ? 220 : 520, kind: item.kind, inset: 7, symbolSize: 30)
                .frame(height: 120)
                .background(Solanum.raised, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Solanum.ink : Solanum.hairline,
                                                                         lineWidth: isSelected ? 2 : 1))
                .accessibilityHidden(true)
            Text(item.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Solanum.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(ShelfRules.caption(for: item))
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
            model.selection = item.id
            gridFocused = true
        }
        .id(item.id)
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
        .contextMenu {
            Button("Show Where It Came From") { ShelfActions.showWhereItCameFrom(item) }
                .disabled(Demo.mode != nil)
            Button("Quick Look") { model.selection = item.id; quickLookSelected() }
            Button("Copy") { ShelfActions.copy(item) }
            Divider()
            Button("Open") { NSWorkspace.shared.open(item.fileURL) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.folder]) }
            Divider()
            Button("Remove") { model.selection = item.id; model.removeSelected() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(ShelfRules.caption(for: item))")
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
                    maxHeight: model.finder.isWanted ? max(180, size.height * 0.34) : max(220, size.height * 0.56))
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

/// Search, as a pill.
struct ShelfSearchPill: View {
    @Binding var search: String

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
        .frame(width: 170, height: 26)
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

    /// The file on the pasteboard and, for a picture, the picture too.
    static func copy(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = [item.fileURL as NSURL]
        if item.kind == .figure, let image = NSImage(contentsOf: item.fileURL) { objects.append(image) }
        pasteboard.writeObjects(objects)
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

struct ShelfDetail: View {
    let item: ShelfItem
    @ObservedObject var model: ShelfModel
    @ObservedObject var thumbnails: KeptThumbnails
    let quickLook: KeptQuickLook
    let keep: () -> Void
    let maxHeight: CGFloat
    @State private var copied = false
    @State private var sayingMore = false
    /// The card's height as measured; a guess until then, so it never fills the window for a frame.
    @State private var contentHeight: CGFloat = 230

    private var said: String { item.text.claudeSaid.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var longSaid: Bool { said.count > 170 || said.filter(\.isNewline).count > 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Solanum.ink)
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
                                .padding(.top, 4)
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
                        }
                        Spacer(minLength: 8)
                        buttons
                    }
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                }
                if item.hasMore {
                    Solanum.hairline.frame(height: 1).padding(.top, 18)
                    ShelfExtras(item: item, model: model)
                        .id(item.id)
                        .padding(.top, 16)
                }
            }
            .padding(18)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maxHeight))
        .background(Solanum.raised, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Solanum.strong, lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
        .onChange(of: item.id) { _, _ in
            sayingMore = false
            copied = false
        }
    }

    private var preview: some View {
        ShelfPaper(store: thumbnails, url: item.fileURL, side: item.kind == .figure ? 280 : 560, kind: item.kind, inset: 8, symbolSize: 44)
            .frame(width: 260, height: 170)
            .background(Solanum.raised, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Solanum.hairline, lineWidth: 1))
            .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
            .onTapGesture(count: 2) { quickLook.show([item.fileURL], at: 0) }
            .accessibilityLabel("Preview of \(item.fileName)")
            .help("Drag it into your manuscript, or double-click to preview it")
    }

    private var buttons: some View {
        ShelfFlow(spacing: 6) {
            Button {
                ShelfActions.showWhereItCameFrom(item)
            } label: {
                Text("Show Where It Came From").padding(.horizontal, 2)
            }
            .buttonStyle(SolanumPillStyle(.medium, prominent: true))
            .disabled(Demo.mode != nil)
            .help(item.record.sourceRow == nil
                  ? "The conversation it came from, in Capsid"
                  : "The conversation, at the message that showed it")
            Button(copied ? "Copied" : "Copy") {
                ShelfActions.copy(item)
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .buttonStyle(SolanumPillStyle(.medium))
            .help(item.kind == .figure ? "The file and its picture" : "The file")
            if item.record.files.isEmpty, item.version != nil {
                Button("Keep with Data and Code\u{2026}", action: keep)
                    .buttonStyle(SolanumPillStyle(.medium))
                    .disabled(Demo.mode != nil)
                    .help("Also keep the data it was drawn from and the code that drew it")
            }
            Button("Remove") { model.removeSelected() }
                .buttonStyle(SolanumPillStyle(.medium))
                .help("Moves it to the Trash")
        }
    }
}

/// The legend and the files of an item kept with data and code: today's Kept
/// detail, under the card's main row.
private struct ShelfExtras: View {
    let item: ShelfItem
    @ObservedObject var model: ShelfModel
    @State private var legend = ""
    /// The README as last read, so an edit made elsewhere is never written over.
    @State private var lastRead: String?
    @State private var problem: String?
    @State private var changedOutside = false
    @State private var saveTask: Task<Void, Never>?

    private var record: KeptRecord { item.record }
    private var disk: KeptDisk { model.index.disk }

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
                TextField("The legend you\u{2019}ll use in the paper", text: $legend, axis: .vertical)
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
                    .onChange(of: legend) { _, text in scheduleSave(text) }
                if let problem {
                    note(problem)
                }
                if changedOutside {
                    HStack(spacing: 8) {
                        note("README.md was changed in another app.")
                        Button("Use Mine") { Task { await save(legend, force: true) } }
                        Button("Use Theirs") { Task { await load() } }
                    }
                    .buttonStyle(SolanumPillStyle(.small))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await load() }
        .onDisappear { saveTask?.cancel() }
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

    // MARK: The legend

    private func load() async {
        changedOutside = false
        problem = nil
        guard let read = try? await disk.readme(at: item.folder) else { return }
        lastRead = read.markdown
        legend = read.text.legend
    }

    private func scheduleSave(_ text: String) {
        guard let lastRead, KeptReadme.parse(lastRead)?.text.legend != text else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await save(text, force: false)
        }
    }

    private func save(_ text: String, force: Bool) async {
        var base = lastRead
        if force, let fresh = try? await disk.readme(at: item.folder) { base = fresh.markdown }
        guard let base else { return }
        do {
            lastRead = try await disk.replaceLegend(at: item.folder, with: text, lastRead: base)
            changedOutside = false
            problem = nil
            await model.index.reload(item.result)
        } catch KeptDiskError.changedOutside {
            changedOutside = true
        } catch {
            problem = "Couldn\u{2019}t save the legend: \(KeptDiskError.sentence(error)) Your text is kept here."
        }
    }
}

// MARK: Pieces

/// A picture on paper: Quick Look's, a text file's first lines (`ShelfPeek`),
/// or the kind's symbol until it comes. The paper is white in both appearances
/// (a figure is drawn for it), inset from its card so the card's own ground
/// frames it.
struct ShelfPaper: View {
    @ObservedObject var store: KeptThumbnails
    let url: URL
    let side: CGFloat
    let kind: ShelfKind
    let inset: CGFloat
    let symbolSize: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            Color.white
            if store.usesPeek(url) {
                // Drawn from the file's text; blank until it has been read.
                if let peek = store.peek(for: url) {
                    ShelfPeekView(peek: peek, scale: inset >= 8 ? 1.3 : 1)
                }
            } else if let image = store.image(for: url, side: side) {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: ShelfPaper.symbol(kind))
                    .font(.system(size: symbolSize, weight: .light))
                    .foregroundStyle(Color(nsColor: .systemGray))
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.rect(cornerRadius: max(3, inset - 2)))
        .padding(inset)
        .onAppear {
            if store.usesPeek(url) { store.wantPeek(url) } else { store.want(url, side: side, scale: scale, cropped: kind != .figure) }
        }
        // A file that wasn't text after all goes to Quick Look.
        .onChange(of: store.usesPeek(url)) { _, uses in
            if !uses { store.want(url, side: side, scale: scale, cropped: kind != .figure) }
        }
    }

    static func symbol(_ kind: ShelfKind) -> String {
        switch kind {
        case .figure: "photo"
        case .document: "doc.text"
        case .table: "tablecells"
        }
    }
}

/// A text file's first lines on paper, as board 11 draws a note: a bold
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
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 6 * scale)
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
            if note.removal != nil {
                Button("Undo", action: undo)
                    .buttonStyle(ShelfNoteButtonStyle())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, note.removal == nil ? 16 : 8)
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
