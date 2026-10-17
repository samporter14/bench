// ResultsQuickLook.swift — the real Quick Look panel for the results shelf
// (DESIGN.md, Results). Preview opens `QLPreviewPanel` on a temporary copy
// of the file (ShelfTemporaryCopies); the arrow keys move between the files
// the list shows. Only the file asked for is downloaded: the others are
// listed in the panel without a URL (Quick Look shows its loading view) and
// fetched when the arrow keys reach them, one at a time, through the shelf's
// one download path with its 8 MB cap. Moving on withdraws the want of the
// file left (`ShelfPreviewDemand`): a download for it that hasn't started
// never does, and one under way stops unless a drag, Copy or a save still
// wants it. The Results window is the panel's controller (`ResultsWindow`),
// so Quick Look follows the responder chain as it does in Finder.
import AppKit
import QuickLookUI

/// One file in the panel: its temporary copy's URL once there is one, and
/// the file's real name as the title.
@MainActor
final class ShelfQuickLookItem: NSObject, @preconcurrency QLPreviewItem {
    let entry: ArtifactEntry
    private let copy: @MainActor () -> URL?

    init(entry: ArtifactEntry, copy: @escaping @MainActor () -> URL?) {
        self.entry = entry
        self.copy = copy
    }

    /// Nil until the copy exists: Quick Look shows a loading view meanwhile.
    var previewItemURL: URL! { copy() }
    var previewItemTitle: String! { entry.name }
}

/// What Quick Look wants fetched: one file at a time. Wanting another file
/// withdraws the want of the last (its task is cancelled, which takes back
/// only its own claim on the download): one that hadn't started never does,
/// and one under way stops unless a drag, Copy or a save still wants it.
@MainActor
final class ShelfPreviewDemand {
    private let shelf: ResultsShelf
    /// The file wanted now, while it is being fetched.
    private(set) var version: String?
    private var task: Task<Void, Never>?

    init(shelf: ResultsShelf) {
        self.shelf = shelf
    }

    /// Wants `entry`'s copy, then `done` with it (nil when it can't be had);
    /// `done` isn't called once the want is withdrawn. `pressed` keeps
    /// Preview's rule (a press while it loads does nothing); the panel's
    /// arrow keys join a download already under way. Wanting the file wanted
    /// already changes nothing.
    func want(_ entry: ArtifactEntry, pressed: Bool, then done: @escaping @MainActor (URL?) -> Void) {
        guard version != entry.version else { return }
        withdraw()
        version = entry.version
        task = Task { [weak self, shelf] in
            let url = pressed ? await shelf.prepareQuickLook(entry) : await shelf.previewCopy(entry)
            guard !Task.isCancelled else { return }
            if let self, self.version == entry.version {
                self.version = nil
                self.task = nil
            }
            done(url)
        }
    }

    /// The panel left the file, or the window is closing: nothing more is
    /// fetched for it.
    func withdraw() {
        task?.cancel()
        task = nil
        version = nil
    }
}

@MainActor
final class ResultsQuickLook: NSObject {
    private let shelf: ResultsShelf
    weak var window: NSWindow?
    private(set) var items: [ShelfQuickLookItem] = []
    private var current = 0
    private var observation: NSKeyValueObservation?
    private let demand: ShelfPreviewDemand

    init(shelf: ResultsShelf) {
        self.shelf = shelf
        demand = ShelfPreviewDemand(shelf: shelf)
    }

    // MARK: Preview

    /// Preview: gets the file's temporary copy (a spinner on its row meanwhile;
    /// a second press while it loads does nothing), then shows the panel on it,
    /// with the other files of `entries` a key press away. Pressing Preview on
    /// another file meanwhile withdraws this one.
    func show(_ entry: ArtifactEntry, among entries: [ArtifactEntry]) {
        guard !shelf.preparing.contains(entry.version) else { return }
        demand.want(entry, pressed: true) { [weak self] url in
            guard let self, url != nil else { return }
            self.present(entry, among: entries)
        }
    }

    /// The panel's files: those shown, bar any over the cap, which can't be
    /// previewed here (pressing Preview on one says so on its row).
    static func panelFiles(_ entry: ArtifactEntry, among entries: [ArtifactEntry]) -> [ArtifactEntry] {
        var files = entries.filter { ArtifactGate.download(size: $0.size) == nil }
        if !files.contains(where: { $0.version == entry.version }) { files.append(entry) }
        return files
    }

    private func present(_ entry: ArtifactEntry, among entries: [ArtifactEntry]) {
        let files = Self.panelFiles(entry, among: entries)
        items = files.map { file in
            ShelfQuickLookItem(entry: file) { [shelf] in shelf.cachedCopy(file.version) }
        }
        current = files.firstIndex { $0.version == entry.version } ?? 0
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
        demand.withdraw()
        items = []
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible,
              (panel.currentController as AnyObject?) === window else { return }
        panel.orderOut(nil)
    }

    // MARK: The panel's control (called by ResultsWindow)

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
    }

    /// The panel reached another file: its copy is fetched if it isn't there
    /// yet, and the file it left is wanted no more. One that can't be fetched
    /// leaves the panel; its row says why.
    private func moved(to index: Int) {
        guard items.indices.contains(index) else { return }
        current = index
        let item = items[index]
        let version = item.entry.version
        guard shelf.cachedCopy(version) == nil else {
            demand.withdraw()
            return
        }
        demand.want(item.entry, pressed: false) { [weak self] url in
            guard let self else { return }
            if url != nil {
                if self.items.indices.contains(self.current), self.items[self.current] === item {
                    QLPreviewPanel.shared()?.refreshCurrentPreviewItem()
                }
            } else if self.shelf.fileProblems[version] != nil, let at = self.items.firstIndex(where: { $0 === item }) {
                self.items.remove(at: at)
                QLPreviewPanel.shared()?.reloadData()
            }
        }
    }
}

extension ResultsQuickLook: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items.indices.contains(index) ? items[index] : nil
    }
}
