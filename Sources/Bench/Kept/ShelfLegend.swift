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
        let before = lastSave
        let next = Task { @MainActor in
            await before?.value
            await self.write(force: force)
        }
        lastSave = next
        await next.value
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
        } catch {
            problem = Self.unsaved(KeptDiskError.sentence(error))
        }
    }
}
