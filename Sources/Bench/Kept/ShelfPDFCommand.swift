// ShelfPDFCommand.swift — Make PDF… on the Shelf (DESIGN.md, Shelf → Lab-meeting
// PDF): what happens between the pick and the file. A save panel (Downloads,
// "Lab meeting 2026-10-23.pdf"), the words of each text file read through the
// disk layer, the drawing off the main actor (ShelfPDF.swift), and then the
// file shown in Finder; nothing is opened by itself. A file that can't be read
// or a PDF that can't be saved is one sentence on the Shelf's dark pill, and
// never a PDF with a page quietly missing. The steps that reach outside
// (the panel, the drawing, Finder) are `Dependencies`, so the tests run the
// whole command on fakes.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShelfPDFMaker: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Pages done of the pages to make.
        case making(done: Int, total: Int)
    }

    /// Every step that reaches outside the command.
    struct Dependencies {
        /// Where to save, asked of the person; nil when they cancel.
        var choose: @MainActor (_ suggestedName: String) async -> URL?
        /// Draws the pages into the file, reporting how many are done.
        var render: @Sendable (_ pages: [ShelfPDFPage], _ url: URL, _ title: String, _ progress: @escaping @Sendable (Int) -> Void) async throws -> Void
        /// A text file's first words, for its page.
        var words: @MainActor (_ file: URL) async -> String?
        /// Shows the file in Finder.
        var reveal: @MainActor (_ file: URL) -> Void
        var now: @MainActor () -> Date
        var calendar: Calendar
        var locale: Locale

        /// The real ones: the save panel as a sheet on the key window, the drawing on its own queue, Finder.
        @MainActor
        static func live(words: @escaping @MainActor (URL) async -> String?) -> Dependencies {
            Dependencies(
                choose: { name in await ShelfPDFMaker.savePanel(suggestedName: name) },
                render: { pages, url, title, progress in try await ShelfPDF.make(pages, to: url, title: title, progress: progress) },
                words: words,
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                now: { Date() }, calendar: .current, locale: .current)
        }
    }

    @Published private(set) var phase: Phase = .idle
    private var dependencies: Dependencies
    /// The save panel is up: a second ask waits for it.
    private var asking = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// The real command, reading text files through `disk`.
    static func live(disk: KeptDisk) -> ShelfPDFMaker {
        ShelfPDFMaker(dependencies: .live(words: { url in (try? await disk.peek(url, limit: ShelfPDFMaker.textBytes)) ?? nil }))
    }

    /// How much of a text file a page can use.
    static let textBytes = 20_000

    var isMaking: Bool { phase != .idle }

    /// Asks where to save, makes the PDF of `items` (a page each, in the order given) and shows it in
    /// Finder. `tell` gets the one sentence when it can't be made. Nothing happens while another PDF is
    /// being made, or when the person cancels the panel.
    func make(_ items: [ShelfItem], tell: @MainActor (String) -> Void) async {
        guard !isMaking, !asking else { return }
        guard !items.isEmpty else { return tell(ShelfPDFRules.nothingChosen) }
        let now = dependencies.now()
        asking = true
        let chosen = await dependencies.choose(ShelfPDFRules.fileName(on: now, calendar: dependencies.calendar))
        asking = false
        guard let url = chosen else { return }
        phase = .making(done: 0, total: items.count)
        defer { phase = .idle }
        var text: [String: String] = [:]
        for item in items where ShelfPeek.proseExtensions.contains((item.fileName as NSString).pathExtension.lowercased()) {
            if let words = await dependencies.words(item.fileURL) { text[item.id] = words }
        }
        let pages = ShelfPDFRules.pages(for: items, text: text, locale: dependencies.locale, calendar: dependencies.calendar)
        let total = items.count
        let title = (url.lastPathComponent as NSString).deletingPathExtension
        do {
            try await dependencies.render(pages, url, title.isEmpty ? "Lab meeting" : title) { [weak self] done in
                Task { @MainActor in self?.progressed(done, of: total) }
            }
        } catch ShelfPDF.Failure.unreadable(let name) {
            return tell(ShelfPDFRules.couldntRead(name))
        } catch {
            return tell(ShelfPDFRules.couldntSave(in: Self.folderName(of: url)))
        }
        dependencies.reveal(url)
    }

    /// The drawing's report; a late one never overwrites the end of the job.
    private func progressed(_ done: Int, of total: Int) {
        if isMaking { phase = .making(done: done, total: total) }
    }

    /// "Downloads", from the folder the PDF was to go in.
    static func folderName(of file: URL) -> String {
        let name = file.deletingLastPathComponent().lastPathComponent
        return name.isEmpty || name == "/" ? "that folder" : name
    }

    // MARK: The panel

    /// The save panel, as a sheet on the key window when there is one: Downloads, and the day's name.
    static func savePanel(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = URL.downloadsDirectory
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = "Make PDF"
        panel.message = "One figure on each page, 16:9, for lab meeting."
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let done: @MainActor (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
            // The Shelf's own window, whichever is key.
            if let window = (NSApp.keyWindow as? KeptWindow) ?? NSApp.windows.first(where: { $0 is KeptWindow && $0.isVisible }) {
                panel.beginSheetModal(for: window) { response in MainActor.assumeIsolated { done(response) } }
            } else {
                panel.begin { response in MainActor.assumeIsolated { done(response) } }
            }
        }
    }
}
