// CompareWithTests.swift: the Shelf's ways into Compare (Kept/CompareRules.swift,
// CompareWindow.swift, ShelfPicking.swift): Compare With in one card's menu (the
// cards shown that pair with it, in the Shelf's order and narrowed by its search,
// project and kind, never itself, at most twelve; dimmed with why when none; no
// item on a kind Compare can't read), each entry's words on one line, this card
// on the left, Compare on two picks just as before, and the title bar's Compare
// pill. Made-up items only; nothing is opened.
import Foundation
import Testing
@testable import Bench

@MainActor
struct CompareWithTests {
    /// An hour after the fixtures were kept, in UTC, in English: entries' times are stable.
    private let now = Date(timeIntervalSince1970: 1_800_000_000 + 3_600)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")

    private func offer(_ item: ShelfItem, pair: (ShelfItem, ShelfItem)? = nil, shown: [ShelfItem], filtered: Bool = false,
                       limit: Int = CompareRules.compareWithLimit) -> CompareRules.Offer {
        CompareRules.offer(for: item, pickedPair: pair, shown: shown, filtered: filtered, limit: limit, now: now,
                           calendar: calendar, locale: locale)
    }

    private func entries(_ offer: CompareRules.Offer) -> [CompareRules.Entry] {
        if case .compareWith(let entries) = offer { return entries }
        return []
    }

    // MARK: Which cards are listed

    @Test func compareWithListsOnlyTheShownCardsThatPairAndNeverTheCardItself() {
        let chart = CompareFixtures.item("z_prime_by_plate.png"), heatmap = CompareFixtures.item("plate_7_heatmap.JPG")
        let notes = CompareFixtures.item("qc_notes.md"), log = CompareFixtures.item("run_log.txt"), note = CompareFixtures.item("note.md", version: nil)
        let others = ["receptors.xlsx", "z_prime_by_plate.csv", "plot_z_prime.py"].map { CompareFixtures.item($0) }
        let svg = CompareFixtures.item("figure.svg"), pdf = CompareFixtures.item("z_prime_by_plate.pdf")
        let blot = CompareFixtures.item("knockdown_blot.png")
        let shown = [notes, chart, svg] + others + [heatmap, pdf, log, note, blot]
        // A figure: the other figures (pictures, PDFs, SVGs), in the order shown; not itself, not a note or a table.
        #expect(entries(offer(chart, shown: shown)).map(\.right.id) == [svg.id, heatmap.id, pdf.id, blot.id])
        // A PDF lists the PNG of the same figure, and the rest.
        #expect(entries(offer(pdf, shown: shown)).map(\.right.id) == [chart.id, svg.id, heatmap.id, blot.id])
        // A text file: the other text files, a note among them.
        #expect(entries(offer(notes, shown: shown)).map(\.right.id) == [log.id, note.id])
        #expect(CompareRules.candidates(for: note, in: shown).map(\.id) == [notes.id, log.id])
        // Every entry is a pair Compare reads.
        for item in [chart, notes, heatmap, log, note, blot, svg, pdf] {
            for entry in entries(offer(item, shown: shown)) {
                #expect(entry.right.id != item.id)
                #expect(CompareRules.pairing(entry.left, entry.right) != .notComparable)
            }
        }
    }

    @Test func compareWithFollowsTheShownOrderAndStopsAtItsLimit() {
        let pictures = (1...20).map { CompareFixtures.item("plate_\($0).png") }
        #expect(CompareRules.compareWithLimit == 12)
        // The card among the first twelve: the first twelve others, in order.
        let fifth = pictures[4]
        let listed = entries(offer(fifth, shown: pictures)).map(\.right.id)
        #expect(listed.count == 12)
        #expect(listed == pictures.filter { $0.id != fifth.id }.prefix(12).map(\.id))
        // Further down: still the first twelve shown, not its neighbours.
        #expect(entries(offer(pictures[18], shown: pictures)).map(\.right.id) == pictures.prefix(12).map(\.id))
        // Reversed shown order, reversed list.
        let reversed = Array(pictures.reversed())
        #expect(entries(offer(fifth, shown: reversed)).map(\.right.id) == reversed.filter { $0.id != fifth.id }.prefix(12).map(\.id))
        // Fewer than the limit: all of them.
        #expect(entries(offer(fifth, shown: Array(pictures.prefix(6)))).count == 5)
        #expect(CompareRules.candidates(for: fifth, in: pictures, limit: 3).count == 3)
    }

    @Test func nothingToPairWithDimsCompareWithAndSaysWhy() {
        let chart = CompareFixtures.item("z_prime_by_plate.png"), notes = CompareFixtures.item("qc_notes.md")
        let table = CompareFixtures.item("z_prime_by_plate.csv")
        // The only figure on the Shelf.
        #expect(offer(chart, shown: [chart, notes, table]) == .nothingToCompareWith(help: "There\u{2019}s no other figure on the Shelf to compare with."))
        #expect(offer(notes, shown: [chart, notes, table]) == .nothingToCompareWith(help: "There\u{2019}s no other text file on the Shelf to compare with."))
        // The only one shown, with a search or a filter on: the help says so.
        guard case .nothingToCompareWith(let help) = offer(chart, shown: [chart], filtered: true) else {
            Issue.record("a lone picture should have Compare With dimmed")
            return
        }
        #expect(help.hasPrefix("No other figure is shown"))
        #expect(!help.contains("\u{2014}") && !help.contains("'"))
    }

    @Test func aCardCompareCantReadHasNoItem() {
        let pictures = [CompareFixtures.item("z_prime_by_plate.png"), CompareFixtures.item("plate_7_heatmap.png")]
        for file in ["receptors.xlsx", "z_prime_by_plate.csv", "plot_z_prime.py", "page.html", "README"] {
            let item = CompareFixtures.item(file)
            #expect(offer(item, shown: pictures + [item]) == .none, "\(file)")
        }
    }

    // MARK: Two picked

    @Test func twoPickedWithThisCardAmongThemIsCompareAsBeforeAndNotCompareWith() {
        let chart = CompareFixtures.item("z_prime_by_plate.png"), heatmap = CompareFixtures.item("plate_7_heatmap.png")
        let blot = CompareFixtures.item("knockdown_blot.png"), notes = CompareFixtures.item("qc_notes.md")
        let table = CompareFixtures.item("z_prime_by_plate.csv")
        let shown = [chart, heatmap, blot, notes, table]
        // Two pictures picked: Compare on either, left and right as the Shelf shows them.
        #expect(offer(chart, pair: (chart, heatmap), shown: shown) == .compare(left: chart, right: heatmap))
        #expect(offer(heatmap, pair: (chart, heatmap), shown: shown) == .compare(left: chart, right: heatmap))
        // A picture and a note, or a picture and a table: the dimmed reason, on a card Compare can't read too.
        #expect(offer(chart, pair: (chart, notes), shown: shown) == .unavailable)
        #expect(offer(notes, pair: (chart, notes), shown: shown) == .unavailable)
        #expect(offer(table, pair: (chart, table), shown: shown) == .unavailable)
        // A card outside the two: its own Compare With (or nothing, for a kind Compare can't read).
        #expect(entries(offer(blot, pair: (chart, heatmap), shown: shown)).map(\.right.id) == [chart.id, heatmap.id])
        #expect(offer(table, pair: (chart, heatmap), shown: shown) == .none)
        // The menu's words for the two-pick case are the ones it had.
        #expect(CompareRules.menuTitle == "Compare")
        #expect(CompareRules.unavailableTitle == "Compare (Two Figures or Two Text Files)")
    }

    // MARK: The entries

    @Test func compareWithPutsThisCardOnTheLeftAndTheChosenOneOnTheRight() {
        let chart = CompareFixtures.item("z_prime_by_plate.png"), heatmap = CompareFixtures.item("plate_7_heatmap.png")
        let blot = CompareFixtures.item("knockdown_blot.png")
        let listed = entries(offer(heatmap, shown: [chart, heatmap, blot]))
        #expect(listed.map(\.left.id) == [heatmap.id, heatmap.id])
        #expect(listed.map(\.right.id) == [chart.id, blot.id])
        #expect(listed.map(\.id) == [chart.id, blot.id])
    }

    @Test func eachEntryIsTheNameAndTheCardsCaptionInBracketsOnOneLine() throws {
        let when = ShelfRules.when(Date(timeIntervalSince1970: 1_800_000_000), now: now, calendar: calendar, locale: locale)
        let chart = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC")
        #expect(CompareRules.entryTitle(for: chart, now: now, calendar: calendar, locale: locale)
            == "z_prime_by_plate.png (Plate reader QC \u{00B7} \(when))")
        // No session: the name and the time.
        let bare = CompareFixtures.item("plate_7_heatmap.png", session: "  ")
        #expect(CompareRules.entryTitle(for: bare, now: now, calendar: calendar, locale: locale) == "plate_7_heatmap.png (\(when))")
        // A session over two lines, and a long one: one line, cut at its end.
        let long = CompareFixtures.item("de_heatmap.png", session: "Differential expression,\nknockout against wild type, all twelve samples")
        let title = CompareRules.entryTitle(for: long, now: now, calendar: calendar, locale: locale)
        #expect(!title.contains("\n"))
        #expect(title.hasPrefix("de_heatmap.png (Differential expression, knockout"))
        #expect(title.contains("\u{2026} \u{00B7} "))
        // A long name: cut in the middle, its extension kept.
        let named = CompareFixtures.item("plate_reader_z_prime_by_plate_with_the_edge_wells_masked_out.png")
        let name = try #require(CompareRules.entryTitle(for: named, now: now, calendar: calendar, locale: locale)
            .components(separatedBy: " (").first)
        #expect(name.count == CompareRules.entryNameLimit)
        #expect(name.hasPrefix("plate_reader_z_prime") && name.hasSuffix("masked_out.png") && name.contains("\u{2026}"))
        // Two that would read the same say their versions; one that doesn't, doesn't.
        let blot = CompareFixtures.item("knockdown_blot.png", session: "Western blot quantification")
        let first = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC", version: 2)
        let second = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC", version: 3)
        let other = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC, repeat", version: 1)
        let titles = entries(offer(blot, shown: [blot, first, second, other])).map(\.title)
        #expect(titles == [
            "z_prime_by_plate.png (Plate reader QC \u{00B7} \(when) \u{00B7} version 2)",
            "z_prime_by_plate.png (Plate reader QC \u{00B7} \(when) \u{00B7} version 3)",
            "z_prime_by_plate.png (Plate reader QC, repeat \u{00B7} \(when))",
        ])
        #expect(Set(titles).count == titles.count)
        // One that would read the same as the card itself says its version too, so it isn't mistaken for the card.
        let fromCard = entries(offer(first, shown: [first, second, other])).map(\.title)
        #expect(fromCard.first == "z_prime_by_plate.png (Plate reader QC \u{00B7} \(when) \u{00B7} version 3)")
        #expect(fromCard.last == "z_prime_by_plate.png (Plate reader QC, repeat \u{00B7} \(when))")
    }

    // MARK: On a Shelf

    /// The demo's made-up shelf, in a temporary root.
    private func demoShelf() async -> (model: ShelfModel, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compare-with-\(UUID().uuidString)", isDirectory: true)
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        return (ShelfModel(shelf: KeptDemo.shelf(index: index, root: root), pdf: ShelfPDFMaker(dependencies: .declining)), root)
    }

    private func listed(_ model: ShelfModel, _ item: ShelfItem) -> [String] {
        entries(model.compareOffer(for: item)).map(\.right.fileName)
    }

    @Test func onTheShelfCompareWithFollowsWhatIsShownItsOrderSearchAndProject() async throws {
        let (model, root) = await demoShelf()
        defer { try? FileManager.default.removeItem(at: root) }
        func named(_ file: String) throws -> ShelfItem { try #require(model.shown.first { $0.fileName == file }) }
        let chart = try named("z_prime_by_plate.png")
        // Every other picture shown, in the Shelf's order.
        let pictures = model.shown.filter { $0.id != chart.id && CompareRules.kind(of: $0.fileName) == .images }.map(\.fileName)
        #expect(pictures.count >= 3)
        #expect(listed(model, chart) == pictures)
        #expect(listed(model, try named("qc_notes.md")) == ["methods_draft.md"])
        #expect(model.compareOffer(for: try named("receptors.xlsx")) == .none)
        // A search narrows it.
        model.search = "heatmap"
        #expect(listed(model, try named("plate_7_heatmap.png")) == ["de_heatmap.png"])
        // So does the project, down to nothing: dimmed, and the help says it is what is shown.
        model.search = ""
        model.project = "Knockdown validation"
        guard case .nothingToCompareWith(let help) = model.compareOffer(for: try named("knockdown_blot.png")) else {
            Issue.record("a lone picture in its project should have Compare With dimmed")
            return
        }
        #expect(help.hasPrefix("No other figure is shown"))
        model.project = "Assay development"
        #expect(listed(model, try named("z_prime_by_plate.png")) == ["plate_7_heatmap.png"])
        #expect(model.compareOffer(for: try named("qc_notes.md")) == .nothingToCompareWith(help: CompareRules.nothingToCompareWithHelp(.text, filtered: true)))
    }

    @Test func onTheShelfTwoPicksKeepTheirCompareAndOtherCardsTheirCompareWith() async throws {
        let (model, root) = await demoShelf()
        defer { try? FileManager.default.removeItem(at: root) }
        func named(_ file: String) throws -> ShelfItem { try #require(model.shown.first { $0.fileName == file }) }
        let chart = try named("z_prime_by_plate.png"), heatmap = try named("plate_7_heatmap.png"), blot = try named("knockdown_blot.png")
        // One picked (the window opens on one): Compare With, as on any card.
        model.pick(heatmap.id, .only)
        #expect(listed(model, heatmap).contains("z_prime_by_plate.png"))
        // Two pictures, picked newest last: Compare, the newer card on the left.
        model.pick(chart.id, .toggle)
        #expect(model.compareOffer(for: heatmap) == .compare(left: chart, right: heatmap))
        #expect(model.compareOffer(for: chart) == .compare(left: chart, right: heatmap))
        #expect(listed(model, blot).contains("z_prime_by_plate.png"))
        // A picture and a note: the dimmed reason on both picks.
        model.pick(chart.id, .only)
        model.pick(try named("qc_notes.md").id, .toggle)
        #expect(model.compareOffer(for: chart) == .unavailable)
        #expect(model.compareOffer(for: try named("qc_notes.md")) == .unavailable)
        // Three picked: each card's own Compare With.
        model.pick(heatmap.id, .toggle)
        #expect(model.pickCount == 3)
        #expect(listed(model, chart).contains("plate_7_heatmap.png"))
    }

    // MARK: The picked card's button

    @Test func theButtonShowsOnlyForExactlyTwoPicksThatPairInTheShelfsOrder() async throws {
        let (model, root) = await demoShelf()
        defer { try? FileManager.default.removeItem(at: root) }
        func named(_ file: String) throws -> ShelfItem { try #require(model.shown.first { $0.fileName == file }) }
        let chart = try named("z_prime_by_plate.png"), heatmap = try named("plate_7_heatmap.png")
        // One: no button (and no picked card, no Export pill either).
        model.pick(heatmap.id, .only)
        #expect(!model.showsCompareButton && model.comparablePair == nil)
        // Two pictures, the older picked first: the button, the newer on the left.
        model.pick(chart.id, .toggle)
        #expect(model.showsCompareButton && model.showsExportPill)
        let pair = try #require(model.comparablePair)
        #expect(pair.0.id == chart.id && pair.1.id == heatmap.id)
        // Three: Export as PDF… alone.
        model.pick(try named("knockdown_blot.png").id, .toggle)
        #expect(!model.showsCompareButton && model.showsExportPill)
        // A picture and a note: two, but they don't pair.
        model.pick(chart.id, .only)
        model.pick(try named("qc_notes.md").id, .toggle)
        #expect(model.pickCount == 2 && model.comparePair != nil)
        #expect(!model.showsCompareButton && model.comparablePair == nil && model.showsExportPill)
        // Two text files.
        model.pick(try named("methods_draft.md").id, .toggle)
        model.pick(chart.id, .toggle)
        #expect(model.showsCompareButton)
        #expect(model.comparablePair.map { [$0.0.fileName, $0.1.fileName] } == ["qc_notes.md", "methods_draft.md"])
        #expect(CompareRules.buttonHelp(.images) != CompareRules.buttonHelp(.text))
    }

    // MARK: The wiring

    /// What the rules can't see: the card's menu draws the offer right after Export … as PDF…, each entry opens this
    /// card on the left, the button opens the pair as ordered and sits on the picked card between Clear and the clay
    /// Export, and the title bar holds Export as PDF… alone.
    @Test func theMenuAndTheButtonAreWiredToTheRules() throws {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let export = try #require(view.range(of: "Button(model.exportName(from: item)) { model.exportPDF(from: item) }"))
        let compare = try #require(view.range(of: "ShelfCompareItem(model: model, item: item)"))
        let open = try #require(view.range(of: "Button(\"Open\") { NSWorkspace.shared.open(item.fileURL) }"))
        #expect(export.upperBound < compare.lowerBound && compare.upperBound < open.lowerBound)
        let toolbar = try #require(view.range(of: "if model.showsExportPill {"))
        #expect(view[toolbar.upperBound...].prefix(300).contains("ShelfExportPDFButton(model: model)"))
        #expect(!view.contains("ShelfComparePill") && !view.contains("comparing:"), "no Compare in the title bar")
        let window = FindRepo.source("Kept/CompareWindow.swift")
        #expect(window.contains("model.compareOffer(for: item)"))
        #expect(window.contains("CompareWindowController.shared.show(entry.left, entry.right, shelf: model.shelf)"))
        #expect(window.contains("CompareWindowController.shared.show(left, right, shelf: model.shelf)"))
        #expect(window.contains("CompareWindowController.shared.show(pair.0, pair.1, shelf: model.shelf)"))
        let picking = FindRepo.source("Kept/ShelfPicking.swift")
        let card = try #require(picking.range(of: "struct ShelfPickedActions: View"))
        let body = picking[card.lowerBound...]
        let clear = try #require(body.range(of: "Button(\"Clear\") { model.pickOnlySelected() }"))
        let button = try #require(body.range(of: "ShelfCompareButton(model: model)"))
        let clay = try #require(body.range(of: "Button(exportTitle) { model.exportPDF() }"))
        #expect(clear.upperBound < button.lowerBound && button.upperBound < clay.lowerBound, "Clear, Compare, then the clay Export")
        #expect(window.contains("model.comparablePair, case .comparable(let kind)"), "the button keeps the pair rule")
    }
}
