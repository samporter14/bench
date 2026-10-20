// ResultsWindow.swift — the results shelf's window (DESIGN.md, Results), opened
// from File → Results… (⇧⌘R), the toolbar's tray, or a card (`show(focusing:)`).
// Sessions by project, recent then older, each with its files: a thumbnail or
// an icon, the name, the kind, the size and the date; Preview (Quick Look, also
// the Space bar), Copy, Save…, drag out to Finder or another app, and once
// saved Open and Reveal in Finder; Save All… on a session; and Open
// Conversation for where it came from.
import AppKit
import QuickLookUI
import SwiftUI

/// The Results window. It takes charge of the Quick Look panel while it is
/// the key or main window (the responder chain finds it) and hands the
/// panel to `ResultsQuickLook`.
final class ResultsWindow: NSWindow {
    var quickLook: ResultsQuickLook?

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook?.begin(panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook?.end(panel) }
    }
}

@MainActor
final class ResultsWindowController: NSObject, NSWindowDelegate {
    static let shared = ResultsWindowController()
    private var window: ResultsWindow?
    private var quickLook: ResultsQuickLook?
    /// The shelf the window shows, which it closes when it closes.
    private var shelf: ResultsShelf?

    func show(shelf: ResultsShelf = .shared) {
        if window == nil {
            let quickLook = ResultsQuickLook(shelf: shelf)
            let hosting = NSHostingController(rootView: ResultsView(shelf: shelf, quickLook: quickLook))
            let window = ResultsWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                                       styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                       backing: .buffered, defer: false)
            window.contentViewController = hosting
            window.title = "Results"
            window.setContentSize(NSSize(width: 760, height: 580))
            window.contentMinSize = NSSize(width: 520, height: 360)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("CapsidResults")
            window.delegate = self
            window.quickLook = quickLook
            quickLook.window = window
            if !window.setFrameUsingName("CapsidResults") { window.center() }
            self.window = window
            self.quickLook = quickLook
            self.shelf = shelf
        }
        // Every opening takes the recent sessions afresh and reads the newest few.
        if window?.isVisible != true { shelf.open() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Opens the window on one session (the Finished card's Results button):
    /// it is in the list, open, read if it wasn't, scrolled to and selected.
    func show(focusing session: SessionStatus, shelf: ResultsShelf = .shared) {
        show(shelf: shelf)
        shelf.focus(session)
    }

    func windowWillClose(_ notification: Notification) {
        // The panel shows a temporary copy that the shelf is about to delete.
        quickLook?.closePanel()
        (shelf ?? .shared).close()
    }
}

/// The toolbar's tray: opens the shelf.
struct ResultsToolbarButton: View {
    var body: some View {
        Button { ResultsWindowController.shared.show() } label: {
            Image(systemName: "tray.full")
                .accessibilityLabel("Results")
        }
        .buttonStyle(ReadoutButtonStyle())
        .help("Results: the files your sessions made (⇧⌘R)")
        .disabled(Demo.mode != nil)
    }
}

// MARK: The window's content

/// What is selected in the list: a session's row, or a file's.
enum ShelfSelection: Hashable {
    case session(String)
    case file(String)
}

/// A search covers only file lists already loaded. Remove unmatched sessions
/// before building project headings, while keeping the original group/order.
enum ShelfResultSearch {
    static func groups(_ groups: [ShelfGroup], matching query: String) -> [ShelfGroup] {
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let matches = group.sessions.filter { item in
                (item.results.entries ?? []).contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
            guard !matches.isEmpty else { return nil }
            return ShelfGroup(coverage: group.coverage, projectID: group.projectID,
                              projectName: group.projectName, sessions: matches)
        }
    }
}

struct ResultsView: View {
    @ObservedObject var shelf: ResultsShelf
    let quickLook: ResultsQuickLook
    @State private var search = ""
    @State private var selection: ShelfSelection?

    var body: some View {
        let groups = ShelfResultSearch.groups(shelf.groups, matching: search)
        VStack(spacing: 0) {
            header
            Divider()
            if !search.isEmpty, groups.isEmpty {
                ContentUnavailableView {
                    Label("No matching files", systemImage: "magnifyingglass")
                } description: {
                    Text("Only loaded results are searched. Clear the search to open more sessions.")
                } actions: {
                    Button("Clear Search") { search = ""; selection = nil }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shelf.sessions.isEmpty, shelf.older == .hidden {
                ContentUnavailableView {
                    Label("No sessions yet", systemImage: "tray")
                } description: {
                    Text("When your sessions make files, they appear here.")
                } actions: {
                    Button("Show Older Sessions") { shelf.showOlder() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(groups)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        // Opening Results for a card must reveal its session, even if the
        // previous visit left a filter that would hide it.
        .onChange(of: shelf.focused) { _, focus in
            if focus != nil { search = "" }
        }
    }

    // MARK: The header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Filter by file name", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Filter results by file name")
                Spacer(minLength: 8)
                Button { shelf.open(refresh: true) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Take the recent sessions again and read the newest")
            }
            Text(search.isEmpty ? shelf.coverageLine
                                : "Filtering the files read so far. Sessions not read yet aren't searched.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !shelf.isReady {
                Label(ShelfFailure.notReady.sentence, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.clayText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: The list

    private func list(_ groups: [ShelfGroup]) -> some View {
        let recent = groups.filter { $0.coverage == .recent }
        let older = groups.filter { $0.coverage == .older }
        return ScrollViewReader { proxy in
            List(selection: $selection) {
                if !recent.isEmpty {
                    Section("Recent sessions") {
                        ForEach(recent) { group in
                            projectRows(group)
                        }
                    }
                }
                if !older.isEmpty || search.isEmpty {
                    Section("Older sessions") {
                        ForEach(older) { group in
                            projectRows(group)
                        }
                        if search.isEmpty { olderFooter }
                    }
                }
            }
            .listStyle(.inset)
            // Space on a selected file opens Quick Look, as in Finder.
            .onKeyPress(.space) { previewSelected() ? .handled : .ignored }
            // Asked to show one session: select it and scroll to it.
            .onChange(of: shelf.focused, initial: true) { _, focus in
                guard let focus else { return }
                selection = .session(focus.sessionID)
                Task { @MainActor in
                    await Task.yield()
                    withAnimation { proxy.scrollTo(focus.sessionID, anchor: .top) }
                }
            }
        }
    }

    @ViewBuilder
    private func projectRows(_ group: ShelfGroup) -> some View {
        Text(group.projectName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
        ForEach(group.sessions) { item in
            sessionRow(item)
                .id(item.id)
                .tag(ShelfSelection.session(item.id))
        }
    }

    private func isOpen(_ item: ShelfSession) -> Bool {
        let hasResults = !(item.results.entries ?? []).isEmpty
        return shelf.disclosure.isOpen(item.id, hasResults: hasResults, searching: !search.isEmpty)
    }

    private func isExpanded(_ item: ShelfSession) -> Binding<Bool> {
        let id = item.id
        return Binding(
            get: {
                guard let current = shelf.sessions.first(where: { $0.id == id }) else { return false }
                return isOpen(current)
            },
            set: { open in
                shelf.setExpanded(id, open: open)
                if open, case .notLoaded? = shelf.sessions.first(where: { $0.id == id })?.results { shelf.load(id) }
            })
    }

    /// The files shown now, in the order shown: what Quick Look's arrow keys
    /// move between.
    private var shownFiles: [ArtifactEntry] {
        shelf.groups.flatMap(\.sessions).filter(isOpen).flatMap { item in
            (item.results.entries ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    private func preview(_ entry: ArtifactEntry) {
        quickLook.show(entry, among: shownFiles)
    }

    private func previewSelected() -> Bool {
        guard case .file(let version)? = selection, let entry = shownFiles.first(where: { $0.version == version }) else {
            return false
        }
        preview(entry)
        return true
    }

    private func sessionRow(_ item: ShelfSession) -> some View {
        DisclosureGroup(isExpanded: isExpanded(item)) {
            sessionContent(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.session.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(sessionLine(item))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let batch = shelf.batches[item.id] {
                        saveAllLine(batch)
                    }
                }
                Spacer(minLength: 8)
                if canSaveAll(item) {
                    Button { saveAll(item) } label: { Image(systemName: "square.and.arrow.down.on.square") }
                        .buttonStyle(.borderless)
                        .disabled(shelf.isSavingAll)
                        .help("Save all of this session's files into a folder")
                        .accessibilityLabel("Save all files of \(item.session.displayTitle)")
                }
                Button { shelf.openSession(item.session) } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .help("Open the conversation in Capsid")
                .accessibilityLabel("Open the conversation \(item.session.displayTitle)")
            }
            .contextMenu {
                if canSaveAll(item) {
                    Button("Save All…") { saveAll(item) }
                        .disabled(shelf.isSavingAll)
                }
                Button("Open Conversation") { shelf.openSession(item.session) }
            }
        }
    }

    /// Save All is offered once a session's results are read and there are some.
    private func canSaveAll(_ item: ShelfSession) -> Bool {
        !(item.results.entries ?? []).isEmpty
    }

    private func saveAll(_ item: ShelfSession) {
        ResultSaving.chooseFolder(for: item, shelf: shelf)
    }

    /// "Saving 3 of 7…", then "Saved 6 files. 1 was too big to save here." and Reveal in Finder.
    private func saveAllLine(_ batch: ShelfSaveAllState) -> some View {
        HStack(spacing: 6) {
            if case .saving = batch { ProgressView().controlSize(.mini) }
            Text(batch.line)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if case .finished(let summary) = batch {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: summary.folder.path)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .help("Show the folder the files were saved to")
            }
        }
    }

    /// "Oct 15, 3:40 PM · 4 files", "… · Not read yet", "… · Reading…".
    private func sessionLine(_ item: ShelfSession) -> String {
        let when = item.session.updatedAt.formatted(date: .abbreviated, time: .shortened)
        let state: String = switch item.results {
        case .notLoaded: "Not read yet"
        case .queued, .loading: "Reading…"
        case .loaded(let entries, _): entries.isEmpty ? "No files" : (entries.count == 1 ? "1 file" : "\(entries.count) files")
        case .failed: "Couldn't read"
        }
        return "\(when) · \(state)"
    }

    @ViewBuilder
    private func sessionContent(_ item: ShelfSession) -> some View {
        switch item.results {
        case .notLoaded:
            Button("Load Results") { shelf.load(item.id) }
                .help("Read this session's files from Claude Science")
        case .queued, .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .loaded(let entries, _) where entries.isEmpty:
            Text("This session hasn't made any files.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .loaded(let entries, _):
            ForEach(entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, id: \.version) { entry in
                ResultFileRow(shelf: shelf, entry: entry, session: item.session, onPreview: { preview(entry) })
                    .tag(ShelfSelection.file(entry.version))
            }
        case .failed(let failure):
            HStack(spacing: 8) {
                Label(failure.sentence, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Try Again") { shelf.load(item.id) }
                if failure == .missing {
                    Button("Open Conversation") { shelf.openSession(item.session) }
                }
            }
        }
    }

    @ViewBuilder
    private var olderFooter: some View {
        switch shelf.older {
        case .hidden:
            Button("Show Older Sessions") { shelf.showOlder() }
                .help("Read older sessions from Claude Science's database, a page at a time")
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading older sessions…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .shown(let next):
            if next != nil {
                Button("Show More") { shelf.showOlder() }
            } else {
                Text("That's every session.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .failed:
            HStack(spacing: 8) {
                Text("Couldn't read older sessions.").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Try Again") { shelf.showOlder() }
            }
        }
    }
}

// MARK: One file

struct ResultFileRow: View {
    @ObservedObject var shelf: ResultsShelf
    let entry: ArtifactEntry
    let session: SessionStatus
    /// Preview: Quick Look on this file.
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ShelfThumbnailView(store: shelf.thumbnailStore, version: entry.version, kind: entry.kind)
                .frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: 6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ResultFileRow.detail(entry))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let problem = shelf.fileProblems[entry.version] {
                    Text(problem)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.clayText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            actions
        }
        .padding(.vertical, 2)
        .onAppear { shelf.wantThumbnail(entry) }
        // The window opened again or Refresh: closing let the pictures go.
        .onChange(of: shelf.takenAt) { shelf.wantThumbnail(entry) }
        // Dragged out, the file is fetched when it is dropped, not when the drag begins.
        .onDrag { ShelfDrag.provider(for: entry, shelf: shelf) }
        .contextMenu {
            Button("Preview") { onPreview() }
                .disabled(shelf.preparing.contains(entry.version))
            if ShelfCopy.isOffered(entry.kind) {
                Button("Copy") { Task { await shelf.copy(entry) } }
                    .disabled(shelf.preparing.contains(entry.version))
            }
            Button("Save…") { ResultSaving.choose(entry, project: session.projectID, shelf: shelf) }
            if shelf.saved[entry.version] != nil {
                Button("Open") { openSaved() }
                Button("Reveal in Finder") { revealSaved() }
            }
            Divider()
            Button("Open Conversation") { shelf.openSession(session) }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if shelf.preparing.contains(entry.version) {
                ProgressView().controlSize(.small).accessibilityLabel("Getting \(entry.name)")
            } else {
                Button { onPreview() } label: { Image(systemName: "eye") }
                    .help("Preview with Quick Look (Space)")
                    .accessibilityLabel("Preview \(entry.name)")
            }
            if shelf.saving.contains(entry.version) {
                ProgressView().controlSize(.small).accessibilityLabel("Saving \(entry.name)")
            } else {
                Button { ResultSaving.choose(entry, project: session.projectID, shelf: shelf) } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save…")
                .accessibilityLabel("Save \(entry.name)")
            }
            if shelf.saved[entry.version] != nil {
                Button { openSaved() } label: { Image(systemName: "arrow.up.forward.app") }
                    .help("Open the saved copy")
                    .accessibilityLabel("Open the saved \(entry.name)")
                Button { revealSaved() } label: { Image(systemName: "folder") }
                    .help("Reveal in Finder")
                    .accessibilityLabel("Reveal the saved \(entry.name) in Finder")
            }
        }
        .buttonStyle(.borderless)
    }

    private func openSaved() {
        if let url = shelf.savedCopy(entry.version) { NSWorkspace.shared.open(url) }
    }

    private func revealSaved() {
        if let url = shelf.savedCopy(entry.version) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    /// "PDF · 1.2 MB · Oct 15, 3:40 PM".
    static func detail(_ entry: ArtifactEntry) -> String {
        [label(entry.kind), ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file),
         entry.at?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · ")
    }

    static func label(_ kind: ArtifactKind) -> String {
        switch kind {
        case .image: "Image"
        case .svg: "SVG image"
        case .markdown: "Markdown"
        case .text: "Text"
        case .table: "Table"
        case .html: "HTML"
        case .pdf: "PDF"
        case .notebook: "Notebook"
        case .other: "File"
        }
    }

    static func symbol(_ kind: ArtifactKind) -> String {
        switch kind {
        case .image: "photo"
        case .svg: "square.on.circle"
        case .markdown: "doc.richtext"
        case .text: "doc.text"
        case .table: "tablecells"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .pdf: "doc.text.image"
        case .notebook: "book.closed"
        case .other: "doc"
        }
    }
}

/// A file's thumbnail, or the icon of its kind. It watches the thumbnail store
/// and nothing else, so the shelf changing (a progress line, another row's
/// state) never reaches it; and it decodes nothing: the store did, once, when
/// the bytes came, and this draws that picture.
struct ShelfThumbnailView: View {
    @ObservedObject var store: ShelfThumbnails
    let version: String
    let kind: ArtifactKind

    var body: some View {
        if let image = store.image(for: version) {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
            Image(systemName: ResultFileRow.symbol(kind))
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.05))
        }
    }
}

/// Save… and Save All…: the panels. A project's panel starts in the folder
/// its files were last saved to (when it is still there), else Downloads.
@MainActor
enum ResultSaving {
    /// Save…: a save panel named as the file, then the shelf writes it there.
    static func choose(_ entry: ArtifactEntry, project: String, shelf: ResultsShelf) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        panel.canCreateDirectories = true
        panel.directoryURL = shelf.startingFolder(for: project) ?? downloads
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await shelf.save(entry, to: url, project: project) }
        }
    }

    /// Save All…: a folder to choose (or make), then the shelf saves the session's files into it.
    static func chooseFolder(for item: ShelfSession, shelf: ResultsShelf) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for this session's files."
        panel.prompt = "Save Here"
        panel.directoryURL = shelf.startingFolder(for: item.session.projectID) ?? downloads
        let id = item.id
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in shelf.saveAll(id, into: url) }
        }
    }

    private static var downloads: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
}
