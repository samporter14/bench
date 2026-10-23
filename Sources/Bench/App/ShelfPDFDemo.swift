// ShelfPDFDemo.swift — `--demo shelf-pdf` (DESIGN.md, Shelf → Lab-meeting PDF):
// the Shelf window on the demo's made-up folders in a temporary root, with two
// figures picked, and the PDF Make PDF… would make from them written into a
// temporary folder (its path is printed). Nothing is read from Claude Science,
// the save panel is never opened, nothing is shown in Finder, and everything
// the demo made is deleted when Capsid quits.
import AppKit
import Foundation

@MainActor
enum ShelfPDFDemo {
    private static var observer: NSObjectProtocol?

    static func show() {
        // The folder the demo owns: the made-up Shelf folder in it, and beside that the PDF.
        let base = URL.temporaryDirectory.appending(path: "Capsid Shelf PDF demo-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = base.appending(path: "Shelf", directoryHint: .isDirectory)
        observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            try? FileManager.default.removeItem(at: base)
        }
        let disk = KeptDisk(root: { root })
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        Task { @MainActor in
            await KeptDemo.seed(disk)
            await index.refreshAndWait()
            KeptWindowController.shared.show(shelf: shelf)
            guard let model = KeptWindowController.shared.model else { return }
            // Two figures: the first card, and the figure after it.
            let figures = model.shown.filter { $0.kind == .figure }
            guard figures.count >= 2 else { return }
            model.pick(figures[0].id, .only)
            model.pick(figures[1].id, .toggle)
            await write(model.pickedItems, in: base, disk: disk)
        }
    }

    /// The PDF of `items`, as Make PDF… makes it, into `folder`.
    private static func write(_ items: [ShelfItem], in folder: URL, disk: KeptDisk) async {
        var text: [String: String] = [:]
        for item in items where item.kind == .document {
            if let words = try? await disk.peek(item.fileURL, limit: ShelfPDFMaker.textBytes) { text[item.id] = words }
        }
        let pages = ShelfPDFRules.pages(for: items, text: text)
        let file = folder.appending(path: ShelfPDFRules.fileName(on: Date()), directoryHint: .notDirectory)
        do {
            try await ShelfPDF.make(pages, to: file)
            print("Capsid demo: wrote \(pages.count) pages to \(file.path)")
        } catch {
            print("Capsid demo: the PDF could not be made (\(error))")
        }
    }
}
