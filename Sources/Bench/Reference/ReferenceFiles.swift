// ReferenceFiles.swift — opening what a reply made (DESIGN.md, Reference): a
// figure in full size in Quick Look, a Markdown document in the window itself
// as a reading view, and any other document (a table, a PDF, a page, a script)
// in Quick Look too.
//
// The reader already knew which files a reply made: `ReferenceRules.answers`
// sorts every file of its steps, turns and messages to the user into the
// pictures it shows (`ReferenceAnswer.figures`) and the rest
// (`ReferenceAnswer.files`). This file says what each is for: the rules are
// pure (`ReferenceFileRules`), and `ReferenceFiles` does the opening for one
// window.
//
// Reads. One path only, the Results shelf's: `ArtifactRead.download` through
// the reference window's own queue (`ReferenceWindowController.transfers`),
// the daemon's bytes within 8 MB, checked again here whatever the listing
// said, and each one through the reading gate (`ReadingGate`): one at a time,
// none within 400 ms of typing in the main window. No route and no page
// script is new.
//
// Writes. Quick Look wants files. The bytes go to a private temporary folder,
// `<temporary folder>/Capsid Reference Files/<UUID>/<version id>/<name>`
// (0700 folders, 0600 files, the real file name kept, the shelf's
// `ShelfTemporaryCopies`), one run per window, and the run's folder is deleted
// when the window closes (and every earlier run's at the first window opened,
// for a window that never got to close). A Markdown document is never
// written: it is decoded in memory, rendered and shown.
import AppKit
import Foundation
import QuickLookUI

// MARK: The rules, pure

enum ReferenceFileRules {
    /// A figure: a picture the daemon draws a thumbnail of. A vector picture
    /// (SVG) is a document: it has no thumbnail, and Quick Look draws it.
    static func isFigure(_ file: HistoryFile) -> Bool {
        ArtifactGate.thumb(kind: file.kind) == nil
    }

    /// Names Claude Science's own file list hides (its plans, its goal pages,
    /// as the artifact list's projection drops them): no document of a reply.
    static func isHidden(_ name: String) -> Bool {
        let lower = name.lowercased()
        return (lower.hasPrefix("plan") && lower.hasSuffix(".json")) || (lower.hasPrefix("goal_") && lower.hasSuffix(".html"))
    }

    /// The reply's documents: the files that aren't pictures, one to an
    /// artifact (the last version), in the order they were made, less the
    /// ones Claude Science hides.
    static func documents(of answer: ReferenceAnswer) -> [HistoryFile] {
        answer.files.filter { !isHidden($0.name) }
    }

    /// A Markdown document is read in the window; everything else is shown
    /// by Quick Look.
    static func readsInWindow(_ file: HistoryFile) -> Bool {
        file.kind == .markdown
    }

    /// What the Quick Look panel pages through for a reply: its figures, then
    /// its documents that Quick Look shows (← and → walk them in that order).
    static func quickLookFiles(figures: [HistoryFile], documents: [HistoryFile]) -> [HistoryFile] {
        figures + documents.filter { !readsInWindow($0) }
    }

    /// The kind tile's word: "MD", "CSV", "PDF"; the file's own ending in
    /// capitals, or its kind (`SinceTile.label`).
    static func tile(_ file: HistoryFile) -> String {
        SinceTile.label(name: file.name, kind: file.kind)
    }

    /// "Markdown · 4 KB".
    @MainActor
    static func detail(_ file: HistoryFile) -> String {
        [ResultFileRow.label(file.kind),
         file.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    // MARK: Reading a document

    /// The most of a document the window reads: the history reads' own cap.
    static let readLimit = HistoryReaderScript.bodyCap

    /// Under a document that was cut.
    static let cutSentence = "Only the first 2 MB are shown. Add it to your shelf for the whole file."
    /// A document with nothing in it.
    static let emptySentence = "This document is empty."
    /// A file over the download cap, by its listing or by its bytes.
    static let tooBigSentence = "Too big to open here (over 8 MB). Open the conversation instead."
    /// The temporary copy couldn't be written.
    static let copySentence = "Couldn\u{2019}t make a copy to show."

    /// A document's bytes as text: UTF-8 (a byte-order mark dropped), at most
    /// `limit` bytes, cut back to a whole character and then to the end of a
    /// line when one ends it within a short way. Nil for bytes that aren't
    /// text (a NUL in the first 8 KB, or not UTF-8).
    static func text(from data: Data, limit: Int = readLimit) -> (text: String, cut: Bool)? {
        guard !data.prefix(8 * 1_024).contains(0) else { return nil }
        var bytes = data.prefix(limit)
        let cut = data.count > limit
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        // A cut can land inside a character: give back up to three bytes of it.
        var decoded: String?
        var drop = 0
        while decoded == nil, drop <= (cut ? 3 : 0), bytes.count - drop >= 0 {
            decoded = String(data: bytes.dropLast(drop), encoding: .utf8)
            drop += 1
        }
        guard var text = decoded else { return nil }
        if cut {
            // Back to the end of a line, when one ends it within a short way.
            let tail = Array(text.utf8.suffix(2_000))
            if let newline = tail.lastIndex(of: 0x0A) {
                text = String(decoding: text.utf8.dropLast(tail.count - newline), as: UTF8.self)
            }
        }
        return (text, cut)
    }

    // MARK: Going back

    /// Esc and ⌘[ leave a document for the answer. Whatever else is held
    /// with them (⇧⌘[, ⌘]) is not a way back.
    static func goesBack(keyCode: UInt16, charactersIgnoringModifiers: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        let held = modifiers.intersection([.command, .shift, .option, .control])
        if keyCode == 53 { return held.isEmpty }
        return held == .command && charactersIgnoringModifiers == "["
    }

    static func goesBack(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        return goesBack(keyCode: event.keyCode, charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                        modifiers: event.modifierFlags)
    }
}

extension HistoryFile {
    /// The file as the shelf's temporary copies name it.
    var entry: ArtifactEntry {
        ArtifactEntry(version: v, artifact: a, name: name, mime: nil, size: size ?? 0, at: nil)
    }
}

// MARK: What a read came to

/// A file's bytes, or why not: what the reference window's download answers.
enum ReferenceDownload: Equatable, Sendable {
    case bytes(Data)
    /// Over the 8 MB cap.
    case tooBig
    case failed(ShelfFailure)
    /// The asker stopped waiting, or the window closed: nothing to say.
    case cancelled

    /// The shelf queue's answer for a download, checked again: bytes within
    /// the cap, whatever the listing said.
    init(_ result: ShelfTransferResult) {
        switch result {
        case .answered(.bytes(let data)):
            switch ArtifactGate.downloadBytes(data) {
            case .success(let bytes): self = .bytes(bytes)
            case .failure: self = .tooBig
            }
        case .answered(.tooBig): self = .tooBig
        case .answered(.cancelled), .cancelled: self = .cancelled
        case .answered(let other): self = .failed(ShelfFailure(other))
        case .timedOut: self = .failed(.timedOut)
        case .notReady: self = .failed(.notReady)
        }
    }
}

/// A Markdown document, read and rendered: the reading view shows it.
struct ReferenceDocument {
    let file: HistoryFile
    let rendered: NSAttributedString
    /// The file was longer than the window reads, and the end is not here.
    let cut: Bool
    let isEmpty: Bool
}

// MARK: Quick Look's items

/// One file in the panel: its temporary copy's URL once there is one, and the
/// file's real name as the title. Nil until the copy exists: Quick Look shows
/// its loading view meanwhile.
@MainActor
final class ReferenceQuickLookItem: NSObject, @preconcurrency QLPreviewItem {
    let file: HistoryFile
    private let copy: @MainActor () -> URL?

    init(file: HistoryFile, copy: @escaping @MainActor () -> URL?) {
        self.file = file
        self.copy = copy
    }

    var previewItemURL: URL! { copy() }
    var previewItemTitle: String! { file.name }
}

// MARK: Opening, for one window

@MainActor
final class ReferenceFiles: NSObject, ObservableObject {
    /// Every window's copies live under one folder of their own, apart from
    /// the Results shelf's ("Capsid Quick Look"), so neither one's cleanup can
    /// reach the other's.
    nonisolated static let folderName = "Capsid Reference Files"
    nonisolated static var defaultBase: URL {
        FileManager.default.temporaryDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// The disk work of the windows, one actor for all of them.
    static let sharedStorage: any ShelfCopyStorage = ShelfTemporaryCopies(base: defaultBase)
    private static var swept = false

    /// The first window of a run deletes what earlier runs left (a window that
    /// never closed). It returns at once; the actor keeps a run that has written
    /// by then, so a copy made first is never taken.
    static func sweepLeftoversOnce() {
        // Not in a demo: the temporary folder is shared with the installed Capsid.
        guard !swept, Demo.mode == nil else { return }
        swept = true
        let storage = sharedStorage
        Task.detached { await storage.removeLeftovers() }
    }

    /// Versions being read now: the card's spinner.
    @Published private(set) var preparing: Set<String> = []
    /// Why a read failed, by version: one sentence under the card.
    @Published private(set) var problems: [String: String] = [:]
    /// The Markdown document open in the window, if any.
    @Published private(set) var document: ReferenceDocument?

    /// The panel's files, in order, and where the last opening was.
    private(set) var items: [ReferenceQuickLookItem] = []
    private(set) var current = 0
    /// Where each version's temporary copy was written.
    private(set) var copies: [String: URL] = [:]
    /// The folder this window's copies are in: `<base>/<run>`.
    let run = UUID()
    weak var window: NSWindow?
    /// Shows the panel on `items` at `current`. Nil is the real panel; tests
    /// record instead of opening one.
    var presenter: (@MainActor (ReferenceFiles) -> Void)?

    private let dependencies: ReferenceDependencies
    private let gate: ReadingGate
    private let storage: any ShelfCopyStorage
    private var fetches: [String: Task<Void, Never>] = [:]
    /// The file the panel's arrow keys want fetched now, if any.
    private var wanted: String?
    private var observation: NSKeyValueObservation?
    /// Bumped by `close`: a read that lands afterwards changes nothing.
    private var token = 0
    /// The folder's deletion, once the window has closed.
    private(set) var removal: Task<Void, Never>?

    init(dependencies: ReferenceDependencies, gate: ReadingGate) {
        self.dependencies = dependencies
        self.gate = gate
        storage = dependencies.storage ?? Self.sharedStorage
        super.init()
    }

    // MARK: Opening

    /// Opens a figure or a document. A figure or a document Quick Look shows
    /// goes to the panel, among `quickLook` (the reply's files, in the order
    /// the panel pages through them); a Markdown document goes into the
    /// window. A second press on a file being read does nothing. Failing
    /// leaves one sentence for the file (`problems`) until the next try.
    func open(_ file: HistoryFile, among quickLook: [HistoryFile]) {
        guard fetches[file.v] == nil else { return }
        problems[file.v] = nil
        preparing.insert(file.v)
        let token = self.token
        fetches[file.v] = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.fetch(file, copyAlready: true)
            guard self.token == token else { return }
            switch outcome {
            case .cancelled: break
            case .failed(let sentence): self.problems[file.v] = sentence
            case .copy:
                self.showInPanel(file, among: quickLook)
            case .bytes(let data):
                if ReferenceFileRules.readsInWindow(file), let text = ReferenceFileRules.text(from: data) {
                    await self.read(file, text: text.text, cut: text.cut, token: token)
                } else if let url = await self.write(data, for: file, token: token) {
                    self.copies[file.v] = url
                    self.showInPanel(file, among: quickLook)
                }
            }
            // The spinner goes when the file is up, or why not is said.
            guard self.token == token else { return }
            self.fetches[file.v] = nil
            self.preparing.remove(file.v)
        }
    }

    /// The reading view's way back.
    func closeDocument() {
        document = nil
    }

    /// Shows a document already read (tests and the demo).
    func show(_ document: ReferenceDocument) {
        self.document = document
    }

    private func read(_ file: HistoryFile, text: String, cut: Bool, token: Int) async {
        let rendered = await dependencies.renderDocument(text)
        guard self.token == token else { return }
        document = ReferenceDocument(file: file, rendered: rendered.text, cut: cut,
                                     isEmpty: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: Reading and writing

    private enum Fetched {
        case bytes(Data)
        /// A temporary copy made earlier in this run is still there.
        case copy
        case failed(String)
        case cancelled
    }

    /// The file's bytes through the gate, the shelf's queue and the cap. With
    /// `copyAlready`, a copy made earlier (and still on disk) stands in.
    private func fetch(_ file: HistoryFile, copyAlready: Bool) async -> Fetched {
        if copyAlready, let url = copies[file.v], !ReferenceFileRules.readsInWindow(file), await storage.exists(url) {
            return .copy
        }
        if let size = file.size, ArtifactGate.download(size: size) != nil { return .failed(ReferenceFileRules.tooBigSentence) }
        let read: ReferenceDownload
        do {
            read = try await gate.perform { [dependencies] in await dependencies.download(file.v) }
        } catch {
            return .cancelled
        }
        switch read {
        case .bytes(let data):
            // Within the cap by its own length, whatever the listing said.
            guard case .success(let bytes) = ArtifactGate.downloadBytes(data) else { return .failed(ReferenceFileRules.tooBigSentence) }
            return .bytes(bytes)
        case .tooBig: return .failed(ReferenceFileRules.tooBigSentence)
        case .failed(let failure): return .failed(failure.sentence)
        case .cancelled: return .cancelled
        }
    }

    /// Writes a temporary copy of the run; nil, with the sentence set, when it
    /// can't be, and nil without one when the window closed meanwhile.
    private func write(_ data: Data, for file: HistoryFile, token: Int) async -> URL? {
        do {
            let url = try await storage.write(data, for: file.entry, run: run)
            guard self.token == token else { return nil }
            if url == nil { problems[file.v] = ReferenceFileRules.copySentence }
            return url
        } catch {
            guard self.token == token else { return nil }
            problems[file.v] = ReferenceFileRules.copySentence
            return nil
        }
    }

    // MARK: The panel

    private func showInPanel(_ file: HistoryFile, among quickLook: [HistoryFile]) {
        var files = quickLook
        if !files.contains(where: { $0.v == file.v }) { files = [file] }
        items = files.map { listed in
            ReferenceQuickLookItem(file: listed) { [weak self] in self?.copies[listed.v] }
        }
        current = files.firstIndex { $0.v == file.v } ?? 0
        if let presenter {
            presenter(self)
        } else {
            present()
        }
    }

    private func present() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, (panel.currentController as AnyObject?) === window {
            panel.reloadData()
            panel.currentPreviewItemIndex = current
            panel.refreshCurrentPreviewItem()
        } else if window?.isKeyWindow == true {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// The window is closing: the panel goes first, because the copy it shows
    /// is about to be deleted.
    func closePanel() {
        withdraw()
        items = []
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible,
              (panel.currentController as AnyObject?) === window else { return }
        panel.orderOut(nil)
    }

    /// The window is closing: nothing more is read, what lands is dropped, the
    /// panel goes, and the run's folder is deleted off the main actor.
    @discardableResult
    func close() -> Task<Void, Never> {
        if let removal { return removal }
        token += 1
        for task in fetches.values { task.cancel() }
        fetches = [:]
        preparing = []
        document = nil
        closePanel()
        copies = [:]
        let storage = storage, run = run
        let removal = Task { await storage.remove(run: run) }
        self.removal = removal
        return removal
    }

    /// The panel's control (called by `ReferenceWindow`).
    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        if items.indices.contains(current) { panel.currentPreviewItemIndex = current }
        // The panel announces the arrow keys only by changing its index.
        observation = panel.observe(\.currentPreviewItemIndex, options: [.new]) { [weak self] panel, _ in
            MainActor.assumeIsolated { self?.moved(to: panel.currentPreviewItemIndex) }
        }
    }

    func end(_ panel: QLPreviewPanel) {
        observation = nil
        panel.dataSource = nil
        withdraw()
    }

    /// The panel reached another file: its copy is fetched if it isn't there
    /// yet, and the file it left is wanted no more. One that can't be fetched
    /// leaves the panel; its card says why.
    func moved(to index: Int) {
        guard items.indices.contains(index) else { return }
        current = index
        let file = items[index].file
        withdraw()
        guard copies[file.v] == nil, fetches[file.v] == nil else { return }
        wanted = file.v
        problems[file.v] = nil
        preparing.insert(file.v)
        let token = self.token
        fetches[file.v] = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.fetch(file, copyAlready: false)
            // Withdrawn while it was read: the panel left the file.
            guard self.token == token, !Task.isCancelled else { return }
            switch outcome {
            case .cancelled, .copy: break
            case .failed(let sentence):
                self.problems[file.v] = sentence
                self.drop(file)
            case .bytes(let data):
                if let url = await self.write(data, for: file, token: token) {
                    self.copies[file.v] = url
                    if self.items.indices.contains(self.current), self.items[self.current].file.v == file.v {
                        self.refreshPanel()
                    }
                } else {
                    self.drop(file)
                }
            }
            guard self.token == token, !Task.isCancelled else { return }
            self.fetches[file.v] = nil
            self.preparing.remove(file.v)
            if self.wanted == file.v { self.wanted = nil }
        }
    }

    /// Withdraws the want of the file the panel left: a read for it that
    /// hasn't started never does, and one under way stops.
    private func withdraw() {
        guard let version = wanted else { return }
        wanted = nil
        fetches[version]?.cancel()
        fetches[version] = nil
        preparing.remove(version)
    }

    /// A file that can't be had leaves the panel.
    private func drop(_ file: HistoryFile) {
        guard let at = items.firstIndex(where: { $0.file.v == file.v }) else { return }
        items.remove(at: at)
        if current >= items.count { current = max(0, items.count - 1) }
        guard presenter == nil, QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared()?.reloadData()
    }

    private func refreshPanel() {
        guard presenter == nil, QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared()?.refreshCurrentPreviewItem()
    }
}

extension ReferenceFiles: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items.indices.contains(index) ? items[index] : nil
    }
}
