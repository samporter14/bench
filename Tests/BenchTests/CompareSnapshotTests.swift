// CompareSnapshotTests.swift — Compare drawn offscreen (Kept/CompareView.swift):
// the wipe's pixels checked at 0%, 50% and 100% on every run, and, only when
// CAPSID_SNAPSHOT_DIR names a folder, captures of each state in light and dark at
// the window's first size and its least (pictures side by side, Wipe at half,
// two sizes, zoomed and linked, Text Changes, no text changes, a side that can't
// be read) and the Shelf with two cards picked. Made-up files only, from a disk
// in memory; nothing is opened on screen. The title bar is drawn as a stand-in
// above the content, as the Shelf's captures do, with the window's own controls.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct CompareSnapshotTests {
    private struct Window: View {
        let model: CompareModel

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color).frame(width: 12, height: 12) }
                    CompareTitle().padding(.leading, 8)
                    Spacer()
                    CompareControls(model: model)
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Solanum.bar)
                .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                CompareView(model: model)
            }
            .background(Solanum.page)
        }
    }

    /// Draws `view` at `size` points, twice the pixels, in light or dark.
    private func render<V: View>(_ view: V, size: NSSize, dark: Bool) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    // MARK: Wipe's pixels

    @Test func wipeShowsTheLeftPictureLeftOfTheDividerAndNeitherMoves() async throws {
        // Left: red, its green channel counting the columns; right: blue, the same count. 200 × 100 in a 200 × 100 pane.
        let left = try CompareImages.decode(CompareFixtures.png(width: 200, height: 100) { x, _ in (230, UInt8(x), 20) }).get()
        let right = try CompareImages.decode(CompareFixtures.png(width: 200, height: 100) { x, _ in (20, UInt8(x), 230) }).get()
        let size = CGSize(width: 200, height: 100)
        let rect = CompareGeometry.imageRect(image: left.source, view: size, viewport: .fit)
        #expect(rect == CGRect(x: 0, y: 0, width: 200, height: 100))
        for fraction in [0.0, 0.5, 1.0] {
            let x = CompareWipe.x(fraction, width: size.width)
            let view = CompareWipeImages(left: left, right: right, rect: rect, x: x, height: size.height).frame(width: 200, height: 100)
            let rep = try await render(view, size: size, dark: false)
            for column in [10, 60, 98, 102, 140, 190] {
                let colour = try #require(rep.colorAt(x: column * 2 + 1, y: 100)?.usingColorSpace(.sRGB))
                let red = colour.redComponent * 255, green = colour.greenComponent * 255, blue = colour.blueComponent * 255
                let fromLeft = CGFloat(column) < x
                #expect(fromLeft ? red > 180 && blue < 80 : blue > 180 && red < 80, "column \(column) at \(fraction)")
                // The column shows its own pixel, wherever the divider is.
                #expect(abs(green - CGFloat(column)) < 6, "column \(column) at \(fraction): green \(green)")
            }
        }
    }

    // MARK: Captures

    private static let notesBefore = """
    # Plate reader QC, 21 October

    Eleven plates pass with Z\u{2032} between 0.62 and 0.78.
    Plate 7 fails because of an edge effect in column 12.

    ## Next steps

    - Repeat plate 7 with a fresh seal.
    - Check the incubator\u{2019}s humidity log.
    - Keep the original export.

    | Plate | Z\u{2032} |
    |---|---|
    | 6 | 0.71 |
    | 7 | 0.41 |
    | 8 | 0.74 |

    Readings are from the 21 October run.

    """

    private static let notesAfter = """
    # Plate reader QC, 22 October

    Twelve plates pass with Z\u{2032} between 0.62 and 0.81.
    Plate 7 passes on the repeat, at Z\u{2032} 0.66.

    ## Next steps

    - Check the incubator\u{2019}s humidity log.
    - Keep the original export beside the repeat.
    - Note the new seal\u{2019}s lot number.

    | Plate | Z\u{2032} |
    |---|---|
    | 6 | 0.71 |
    | 7 | 0.66 |
    | 8 | 0.74 |

    Readings are from the 21 October run.

    """

    private func capture(_ model: CompareModel, _ name: String, minimum: Bool = false, to directory: URL) async throws {
        let size = minimum ? NSSize(width: CompareWindowController.minimum.width, height: CompareWindowController.minimum.height + 52)
                           : NSSize(width: CompareWindowController.size.width, height: CompareWindowController.size.height + 52)
        for dark in [false, true] {
            let rep = try await render(Window(model: model), size: size, dark: dark)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)\(minimum ? "-minimum" : "")-\(dark ? "dark" : "light").png"))
        }
    }

    @Test func eachStateIsDrawnWhenAsked() async throws {
        guard let destination = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !destination.isEmpty else { return }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let disk = CompareFakeDisk()
        let before = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC", version: 2)
        let after = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC, repeat", version: 3)
        let square = CompareFixtures.item("plate_7_layout.png", session: "Assay development", version: nil)
        let gone = CompareFixtures.item("z_prime_rerun.png", session: "Plate reader QC, repeat", version: 1)
        disk.put(CompareFixtures.chart(width: 960, height: 640, low: 0.30), at: before.fileURL)
        disk.put(CompareFixtures.chart(width: 960, height: 640, low: 0.66), at: after.fileURL)
        disk.put(CompareFixtures.chart(width: 600, height: 600, low: 0.5), at: square.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })

        // Pictures side by side, with Wipe offered.
        model.compare(before, after)
        await model.settle()
        try await capture(model, "side-by-side", to: directory)
        try await capture(model, "side-by-side", minimum: true, to: directory)
        // Zoomed in, linked: the same place in both.
        model.zoom(before.id, by: 3, at: CGPoint(x: 300, y: 330), view: CGSize(width: 507, height: 560))
        try await capture(model, "zoomed-linked", to: directory)
        model.fit()
        // Wipe, at half.
        model.setWiping(true)
        model.wipeFraction = 0.5
        try await capture(model, "wipe-50", to: directory)
        try await capture(model, "wipe-50", minimum: true, to: directory)
        // Two sizes: no Wipe.
        model.compare(before, square)
        await model.settle()
        try await capture(model, "unequal", to: directory)
        // A PNG beside a PDF of the same figure (three pages, the first shown): side by side, sizes in their units.
        let paper = CompareFixtures.item("z_prime_by_plate.pdf", session: "Plate reader QC, repeat", version: 3)
        disk.put(CompareFixtures.chartPDF(low: 0.66, pages: 3), at: paper.fileURL)
        model.compare(before, paper)
        await model.settle()
        #expect(model.sides.last?.content.image?.unit == .points && !model.canWipe)
        try await capture(model, "png-beside-pdf", to: directory)
        try await capture(model, "png-beside-pdf", minimum: true, to: directory)
        // One side that can't be read.
        model.compare(before, gone)
        await model.settle()
        try await capture(model, "unreadable-side", to: directory)

        // Text Changes.
        let notes = CompareFixtures.item("qc_notes.md", session: "Plate reader QC", version: 2)
        let revised = CompareFixtures.item("qc_notes.md", session: "Plate reader QC, repeat", version: 3)
        let same = CompareFixtures.item("qc_notes_copy.md", session: "Assay development", version: nil)
        let away = CompareFixtures.item("methods_draft.md", session: "Methods for the paper", version: 1)
        disk.put(Self.notesBefore, at: notes.fileURL)
        disk.put(Self.notesAfter, at: revised.fileURL)
        disk.put(Self.notesBefore.replacingOccurrences(of: "\n", with: "\r\n"), at: same.fileURL)
        disk.put(Data("# Methods".utf8), at: away.fileURL, putAway: true)
        model.compare(notes, revised)
        await model.settle()
        try await capture(model, "text-changes", to: directory)
        try await capture(model, "text-changes", minimum: true, to: directory)
        model.nextChange()
        model.nextChange()
        try await capture(model, "text-changes-next", to: directory)
        model.compare(notes, same)
        await model.settle()
        #expect(model.outcome == .identical)
        try await capture(model, "no-text-changes", to: directory)
        model.compare(notes, away)
        await model.settle()
        try await capture(model, "text-unreadable-side", to: directory)
    }

    /// The title bar the Shelf window draws, as a stand-in (the toolbar is the window's): the three dots, "Shelf", the
    /// project pill, and at the right the real Export as PDF… pill and the search pill.
    private struct ShelfBar: View {
        @ObservedObject var model: ShelfModel
        let width: CGFloat
        /// Drawn as narrow as its contents go, to measure what the bar needs.
        var measuring = false

        var body: some View {
            if measuring { bar.fixedSize() } else { bar.frame(width: width, height: 52) }
        }

        private var bar: some View {
            HStack(spacing: 10) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color).frame(width: 12, height: 12) }
                // The window's own item is fixed in size: it never wraps, so a bar too full runs off the edge.
                HStack(spacing: 10) {
                    Text("Shelf").font(.system(size: 15, weight: .semibold)).foregroundStyle(Solanum.ink).padding(.leading, 8)
                    ShelfProjectPill(model: model)
                }
                .fixedSize()
                Spacer(minLength: 0)
                if model.showsExportPill { ShelfExportPDFButton(model: model) }
                ShelfSearchPill(search: .constant(model.search), width: ShelfSearchPill.width(forWindow: width))
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Solanum.bar)
            .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
        }
    }

    /// What the stand-in bar needs, in points, at `width`: its pieces side by side with nothing between.
    private func needed(_ model: ShelfModel, at width: CGFloat) -> CGFloat {
        NSHostingView(rootView: ShelfBar(model: model, width: width, measuring: true)).fittingSize.width
    }

    /// What the picked card's row needs, in points, with its caption wrapped: "2 selected", the least gap, the actions
    /// (Clear, Compare, Export, never cut short), the card's own padding and the window's gutters.
    private func pickedCardNeeds(_ model: ShelfModel) -> CGFloat {
        let title = NSHostingView(rootView: Text("\(model.pickCount) selected").font(.system(size: 16, weight: .semibold))).fittingSize.width
        let actions = NSHostingView(rootView: ShelfPickedActions(model: model, exportTitle: ShelfPDFRules.exportName(count: model.pickCount),
                                                                 making: false)).fittingSize.width
        return title + 12 + actions + 2 * 18 + 2 * ShelfRules.gutter
    }

    @Test func theShelfWithTwoPickedIsDrawnWhenAsked() async throws {
        guard let destination = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !destination.isEmpty else { return }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compare-shelf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let model = ShelfModel(shelf: KeptDemo.shelf(index: index, root: root), pdf: ShelfPDFMaker(dependencies: .declining))
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        let chart = try #require(model.shown.first { $0.fileName == "z_prime_by_plate.png" })
        let heatmap = try #require(model.shown.first { $0.fileName == "plate_7_heatmap.png" })

        func shelf(_ name: String, widths: [CGFloat] = [KeptWindowController.size.width]) async throws {
            for width in widths {
                let size = NSSize(width: width, height: 872)
                let suffix = width < KeptWindowController.size.width ? "-minimum" : ""
                for dark in [false, true] {
                    let view = VStack(spacing: 0) {
                        ShelfBar(model: model, width: width)
                        ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook())
                    }
                    .background(Solanum.page)
                    let rep = try await render(view, size: size, dark: dark)
                    let png = try #require(rep.representation(using: .png, properties: [:]))
                    try png.write(to: directory.appendingPathComponent("\(name)\(suffix)-\(dark ? "dark" : "light").png"))
                }
            }
        }

        // One card, the pointer on another: that card's open pick circle.
        model.pick(chart.id, .only)
        model.hoveredCard = heatmap.id
        #expect(model.pickCircle(for: heatmap.id) == .open && model.pickCircle(for: chart.id) == .hidden)
        try await shelf("shelf-pick-hover")
        // Its circle clicked: two picked, every card with its circle, Compare on the picked card.
        model.pickCircleClicked(heatmap.id)
        model.hoveredCard = nil
        #expect(model.pickCount == 2 && model.showsCompareButton)
        try await shelf("shelf-two-picked", widths: [KeptWindowController.size.width, 620])
        // The picked card's row fits the window's least width, Compare among it.
        let least: CGFloat = 620
        let card = pickedCardNeeds(model)
        #expect(card <= least, "the picked card needs \(card) points at \(least)")
        // And the title bar, with Export as PDF… alone in it.
        let bar = needed(model, at: least)
        #expect(bar <= least, "the bar needs \(bar) points at \(least)")
        for dark in [false, true] {
            let rep = try await render(ShelfBar(model: model, width: 620), size: NSSize(width: 620, height: 52), dark: dark)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("shelf-title-bar-two-picked-minimum-\(dark ? "dark" : "light").png"))
        }
        // A picture and a note picked: no Compare, Clear and Export alone.
        model.pick(try #require(model.shown.first { $0.fileName == "qc_notes.md" }).id, .only)
        model.pick(chart.id, .toggle)
        #expect(model.showsExportPill && !model.showsCompareButton)
        try await shelf("shelf-two-picked-no-pair")
        try ["At \(Int(least)) points wide",
             "The picked card with Clear, Compare and Export: needs \(Int(card.rounded(.up)))",
             "The title bar with Export as PDF\u{2026}: needs \(Int(bar.rounded(.up)))"].joined(separator: "\n")
            .write(to: directory.appendingPathComponent("shelf-picked-widths.txt"), atomically: true, encoding: .utf8)
    }

    /// Context menus can't be drawn offscreen, so Compare With's words are written out for review instead: every card
    /// of the demo shelf and of a made-up shelf with one file name in several sessions, what its menu offers, and a
    /// stand-in of the card's menu with the submenu open beside it, in the menu's font, to judge its width.
    @Test func compareWithsEntriesAreWrittenOutWhenAsked() async throws {
        guard let destination = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !destination.isEmpty else { return }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compare-with-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let model = ShelfModel(shelf: KeptDemo.shelf(index: index, root: root), pdf: ShelfPDFMaker(dependencies: .declining))

        func describe(_ offer: CompareRules.Offer) -> [String] {
            switch offer {
            case .none: return ["  (no item)"]
            case .compare(let left, let right): return ["  \(CompareRules.menuTitle)  [left \(left.title), right \(right.title)]"]
            case .unavailable: return ["  \(CompareRules.unavailableTitle)  [dimmed] help: \(CompareRules.unavailableHelp)"]
            case .nothingToCompareWith(let help): return ["  \(CompareRules.compareWithTitle)  [dimmed] help: \(help)"]
            case .compareWith(let entries): return ["  \(CompareRules.compareWithTitle) \u{25B8}"] + entries.map { "      \($0.title)" }
            }
        }
        var lines = ["Compare With, as each card's menu offers it", "", "## The demo shelf, nothing filtered", ""]
        for item in model.shown { lines += ["\(item.title)  (\(ShelfRules.caption(for: item)))"] + describe(model.compareOffer(for: item)) + [""] }
        model.project = "Knockdown validation"
        lines += ["## The demo shelf, project Knockdown validation", ""]
        for item in model.shown { lines += [item.title] + describe(model.compareOffer(for: item)) + [""] }
        model.project = nil
        let chart = try #require(model.shown.first { $0.fileName == "z_prime_by_plate.png" })
        let heatmap = try #require(model.shown.first { $0.fileName == "plate_7_heatmap.png" })
        let notes = try #require(model.shown.first { $0.fileName == "qc_notes.md" })
        model.pick(chart.id, .only)
        model.pick(heatmap.id, .toggle)
        lines += ["## The demo shelf, two pictures picked", ""]
        for item in [chart, heatmap, notes] { lines += [item.title] + describe(model.compareOffer(for: item)) + [""] }
        model.pick(notes.id, .toggle)
        model.pick(heatmap.id, .toggle)
        lines += ["## The demo shelf, a picture and a note picked", ""]
        for item in [chart, notes, heatmap] { lines += [item.title] + describe(model.compareOffer(for: item)) + [""] }

        // One file name in several sessions and versions, a long session and a long name.
        let made = [
            CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC", version: 2),
            CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC", version: 3),
            CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC, repeat", version: 1),
            CompareFixtures.item("z_prime_by_plate.png", session: "Assay development, second plate reader and the new seals", version: 4),
            CompareFixtures.item("plate_reader_z_prime_by_plate_with_the_edge_wells_masked_out.png", session: "Plate reader QC", version: 1),
            CompareFixtures.item("knockdown_blot.png", session: "Western blot quantification", version: nil),
        ]
        // The blot's menu lists the other five, the two that read alike with their versions.
        let offer = CompareRules.offer(for: made[5], pickedPair: nil, shown: made, filtered: false)
        lines += ["## A made-up shelf: one name in several sessions", ""]
        for card in [made[5], made[0]] {
            lines += ["\(card.title)  (\(card.record.sessionTitle), version \(card.record.figure.index.map(String.init) ?? "none"))"]
                + describe(CompareRules.offer(for: card, pickedPair: nil, shown: made, filtered: false)) + [""]
        }
        try lines.joined(separator: "\n").write(to: directory.appendingPathComponent("compare-with-entries.txt"), atomically: true, encoding: .utf8)

        // The stand-in menu: the card's items, Compare With highlighted, and its submenu beside it.
        guard case .compareWith(let entries) = offer else {
            Issue.record("the made-up shelf should offer Compare With")
            return
        }
        for dark in [false, true] {
            let view = CompareWithMenuStandIn(cardItems: ["Show Where It Came From", "Open as Reference", "Quick Look", "Copy",
                                                          "Export Figure as PDF\u{2026}"],
                                              entries: entries.map(\.title))
            let size = NSSize(width: 820, height: 330)
            let rep = try await render(view.frame(width: size.width, height: size.height, alignment: .topLeading), size: size, dark: dark)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("compare-with-menu-stand-in-\(dark ? "dark" : "light").png"))
        }
    }
}

/// A drawing of a native menu, for review only: the menu's own font and row height, rounded and on the window
/// background, one item highlighted with its submenu beside it. Not the real menu, which only the system draws.
private struct CompareWithMenuStandIn: View {
    let cardItems: [String]
    let entries: [String]

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(5)
            .fixedSize()
            .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private func row(_ title: String, highlighted: Bool = false, submenu: Bool = false) -> some View {
        HStack(spacing: 18) {
            Text(title).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            if submenu { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
        }
        .font(Font(NSFont.menuFont(ofSize: 0)))
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(highlighted ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 4))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            panel {
                ForEach(cardItems, id: \.self) { row($0) }
                row(CompareRules.compareWithTitle, highlighted: true, submenu: true)
                Divider().padding(.vertical, 4)
                row("Open")
                row("Show in Finder")
                Divider().padding(.vertical, 4)
                row("Remove")
            }
            panel {
                ForEach(entries, id: \.self) { row($0) }
            }
            .padding(.top, CGFloat(cardItems.count) * 22)
        }
        .padding(16)
    }
}
