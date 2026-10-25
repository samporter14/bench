// ShelfLegend.swift — the legend field under an item kept with data and code
// (DESIGN.md, Shelf): what is typed, when it is written to the README, and
// what is said when it can't be. The field saves itself a second after the last
// keystroke; leaving it (another item chosen, the window closed) saves at once,
// so a legend typed just before moving on is never lost; and a README that
// can't be read turns the field off with the reason, because nothing typed
// there could ever be saved.
//
// Saves go one at a time, each from what the one before wrote, and each writes
// what the field holds when it runs, not what it held when it was asked for. A
// README changed in another app is never written over: the field offers "Use
// Mine" and "Use Theirs". The editor makes no file-system call of its own;
// `KeptDisk` does, off the main actor.
//
// Claude's legend (ShelfClaudeLegend.swift) goes in through this editor too: `put` is a set-and-save, taken back
// whole when it can't be saved, `list` copies Claude's file beside the figure and lists it in the README in the same
// queue of writes, and `undoPut` puts the legend back unless the person has changed it since.
//
// An editor outlives its field. The Shelf's model keeps one for each item (keyed
// by its folder) for as long as it holds a draft: text a save hasn't taken, a
// save that failed, a README changed elsewhere. Moving to another item hides the
// field and saves what was typed; if that save then fails, the draft and the
// sentence are still here when the item is chosen again, and the window says so
// meanwhile (`failed`). An editor with nothing left to say is let go.
import Foundation

@MainActor
final class ShelfLegendEditor: ObservableObject {
    /// The text in the field. Typing in it starts the wait before a save.
    @Published var legend = "" {
        didSet { if legend != oldValue, !loading { typed() } }
    }
    /// Whether the field takes typing: only once the README has been read.
    @Published private(set) var canEdit = false
    /// A sentence under the field: the README couldn't be read, or the legend couldn't be saved.
    @Published private(set) var problem: String?
    /// The README was changed in another app since it was read.
    @Published private(set) var changedOutside = false

    /// The field is on screen: a failed save is the field's to say, not the window's.
    private(set) var onScreen = false
    /// Saves asked for and not yet over.
    private var inFlight = 0
    /// Called when a save fails with the field off screen: true for a README changed in another app, false for a disk
    /// failure. The Shelf's model puts a line on its dark pill.
    var failed: (@MainActor (_ conflict: Bool) -> Void)?

    /// A put-in of Claude's legend is under way: a save that fails then is the put-in's to say, not the window's.
    private var putting = false
    /// The disk's own sentence for the last save that failed, without the editor's framing.
    private var failure: String?

    /// The README as last read or written, so an edit made elsewhere is never written over.
    private var lastRead: String?
    /// The field is being set from the README: that is not typing.
    private var loading = false
    private var waiting: Task<Void, Never>?
    private var lastSave: Task<Void, Never>?

    private let folder: URL
    private let disk: KeptDisk
    private let delay: Duration
    private let saved: @MainActor () async -> Void

    /// `saved` is called after each save (the shelf reads the folder again). `delay` is the wait after a keystroke.
    init(folder: URL, disk: KeptDisk, delay: Duration = .seconds(1), saved: @escaping @MainActor () async -> Void) {
        self.folder = folder
        self.disk = disk
        self.delay = delay
        self.saved = saved
    }

    // MARK: Reading

    /// The field is shown. A draft kept from a save that didn't go through (or a README changed elsewhere) is shown as
    /// it was left, with its sentence; anything else is read from the README, as it is now.
    func show() async {
        onScreen = true
        // A write under way (Claude's legend going in) is over first, so what is read is what it wrote.
        await lastSave?.value
        if !holdsDraft { await load() }
    }

    /// The field is gone (another item chosen, the window closed): what was typed is saved now, and a failure of that
    /// save is the window's to say.
    func hide() {
        onScreen = false
        flush()
    }

    /// Reads the README into the field. A README that can't be read turns the field off, with the reason.
    func load() async {
        changedOutside = false
        problem = nil
        do {
            let read = try await disk.readme(at: folder)
            lastRead = read.markdown
            loading = true
            legend = read.text.legend
            loading = false
            canEdit = true
        } catch {
            lastRead = nil
            canEdit = false
            problem = Self.unreadable(KeptDiskError.sentence(error))
        }
    }

    static func unreadable(_ sentence: String) -> String {
        "Couldn\u{2019}t read the README, so the legend can\u{2019}t be edited here. \(sentence)"
    }

    /// The window's line for a legend that couldn't be saved after its item was left. One sentence, the item named.
    static func leftUnsaved(_ name: String, conflict: Bool) -> String {
        let short = name.count > 32 ? String(name.prefix(31)) + "\u{2026}" : name
        return conflict
            ? "The legend for \u{201C}\(short)\u{201D} isn\u{2019}t saved: its README changed in another app. Choose the item to decide."
            : "Couldn\u{2019}t save the legend for \u{201C}\(short)\u{201D}. Choose the item to see why; your text is kept."
    }

    static func unsaved(_ sentence: String) -> String {
        "Couldn\u{2019}t save the legend: \(sentence) Your text is kept here."
    }

    // MARK: Saving

    /// The README's own legend, as last read.
    private var written: String? { lastRead.flatMap { KeptReadme.parse($0)?.text.legend } }

    /// Whether the field holds something the README doesn't.
    var hasUnsavedText: Bool {
        guard canEdit, let written else { return false }
        return written != legend
    }

    /// Text that is the person's and isn't saved, or a sentence about why not: what the model keeps the editor for.
    var holdsDraft: Bool { canEdit && (hasUnsavedText || changedOutside || problem != nil) }

    /// Nothing on screen, nothing to save, nothing to say: the model lets it go.
    var isIdle: Bool { !onScreen && inFlight == 0 && !holdsDraft }

    private func typed() {
        guard canEdit else { return }
        waiting?.cancel()
        let delay = delay
        waiting = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.save()
        }
    }

    /// The field is going away: what was typed is saved now, not in a second. The task is the save, for a test to wait for.
    @discardableResult
    func flush() -> Task<Void, Never> {
        waiting?.cancel()
        waiting = nil
        guard hasUnsavedText else { return Task {} }
        // The task holds the editor until the save is done, whether or not the field is still on screen.
        return Task { await self.save() }
    }

    /// Everything typed is written, or has failed, or was stopped by a change made in another app (the field says so),
    /// and every save under way is over: whoever reads the README after this reads what the field holds. A PDF made
    /// from the shelf waits for it. Nothing is ever forced; a README changed elsewhere stays as it is.
    func settle() async {
        await flush().value
        await lastSave?.value
    }

    /// Writes the field's text, after any save already under way.
    func save() async { await enqueue(force: false) }

    /// "Use Mine": the legend as typed goes over the README as it is now.
    func useMine() async { await enqueue(force: true) }

    private func enqueue(force: Bool) async {
        await inOrder { await self.write(force: force) }
    }

    /// `work`, after every write already under way, and before any asked for later: the one queue of writes to the README.
    private func inOrder<Value: Sendable>(_ work: @escaping @MainActor () async -> Value) async -> Value {
        inFlight += 1
        defer { inFlight -= 1 }
        let before = lastSave
        let next = Task { @MainActor in
            await before?.value
            return await work()
        }
        lastSave = Task { @MainActor in _ = await next.value }
        return await next.value
    }

    private func write(force: Bool) async {
        var base = lastRead
        if force, let fresh = try? await disk.readme(at: folder) { base = fresh.markdown }
        guard canEdit, let base else { return }
        let text = legend
        // Nothing to write when the README already says it (typed back to what it was).
        guard force || KeptReadme.parse(base)?.text.legend != text else { return }
        do {
            lastRead = try await disk.replaceLegend(at: folder, with: text, lastRead: base)
            changedOutside = false
            problem = nil
            await saved()
        } catch KeptDiskError.changedOutside {
            changedOutside = true
            failure = KeptDiskError.changedOutside.errorDescription
            if !onScreen, !putting { failed?(true) }
        } catch {
            failure = KeptDiskError.sentence(error)
            problem = Self.unsaved(KeptDiskError.sentence(error))
            if !onScreen, !putting { failed?(false) }
        }
    }

    // MARK: Claude's legend

    /// What `put` came to.
    enum Put: Equatable, Sendable {
        /// The field held `before`, and now holds the new text, saved.
        case saved(before: String)
        /// The field held that text already.
        case unchanged
        /// Nothing was changed; why, in the disk's own words.
        case failed(String)
    }

    /// Puts `text` in the field and saves it at once, as if it were typed and the card then left: the same save, the
    /// same conflict rule, the same bytes written. If it can't be saved it is taken back (the field shows what the README
    /// says), so no draft is left behind for a field that may not even be on screen.
    func put(_ text: String) async -> Put {
        putting = true
        defer { putting = false }
        if !canEdit { await load() }
        guard canEdit else { return .failed(problem ?? Self.unreadable("")) }
        // A save that is waiting on the person (a README changed in another app, a disk that said no) is theirs to settle first.
        if changedOutside { return .failed("Your legend has a save waiting: README.md was changed in another app.") }
        if let why = problem { return .failed(why) }
        let before = legend
        guard before != text else { return .unchanged }
        failure = nil
        legend = text
        await settle()
        if changedOutside || problem != nil {
            let why = failure ?? "The legend couldn\u{2019}t be saved."
            await load()
            return .failed(why)
        }
        return .saved(before: before)
    }

    /// What `list` came to.
    enum Listed: Equatable, Sendable {
        /// The file was copied beside the figure and listed.
        case listed(path: String)
        /// This version of the file was listed already.
        case alreadyListed(path: String)
        /// Nothing was copied or listed; why.
        case failed(String)
    }

    /// Copies `data` into the folder as `file` (a path at the top, role `legend`) and lists it in the README, after any
    /// save already under way, from the README as that save wrote it. The legend is not touched.
    func list(_ data: Data, as file: KeptFile) async -> Listed {
        await inOrder { await self.writeListing(data, file) }
    }

    private func writeListing(_ data: Data, _ file: KeptFile) async -> Listed {
        guard canEdit, let base = lastRead else { return .failed(problem ?? Self.unreadable("")) }
        do {
            let listing = try await disk.listFile(data, as: file, in: folder, lastRead: base)
            lastRead = listing.markdown
            if listing.wasListed { return .alreadyListed(path: listing.path) }
            await saved()
            return .listed(path: listing.path)
        } catch KeptDiskError.changedOutside {
            return .failed("README.md was changed in another app, so the file wasn\u{2019}t listed in it.")
        } catch {
            return .failed(KeptDiskError.sentence(error))
        }
    }

    /// What `undoPut` came to.
    enum Undone: Equatable, Sendable {
        case restored
        /// The legend isn't what was put in any more: it was edited, and is left as it is.
        case edited
        case failed(String)
    }

    /// Puts the legend back to `before`, if it is still `put`, as it was put in.
    func undoPut(_ put: String, restoring before: String) async -> Undone {
        putting = true
        defer { putting = false }
        if !canEdit { await load() }
        guard canEdit else { return .failed(problem ?? Self.unreadable("")) }
        if changedOutside { return .failed("Your legend has a save waiting: README.md was changed in another app.") }
        if let why = problem { return .failed(why) }
        guard legend == put, !hasUnsavedText else { return .edited }
        failure = nil
        legend = before
        await settle()
        if changedOutside || problem != nil {
            let why = failure ?? "The legend couldn\u{2019}t be saved."
            await load()
            return .failed(why)
        }
        return .restored
    }
}
