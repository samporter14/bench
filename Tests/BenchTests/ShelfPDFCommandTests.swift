// ShelfPDFCommandTests.swift — Export Figure as PDF… from the pick to Finder
// (Kept/ShelfPDFCommand.swift), with the panel, the drawing and Finder
// replaced by fakes: what the panel is offered, that cancelling does nothing,
// the pages that reach the drawing and the words of the text files among them,
// the file shown in Finder when it is made and not when it isn't, the one
// sentence for each way it can fail, and that one PDF is made at a time.
import Foundation
import Testing
@testable import Bench

extension ShelfPDFMaker.Dependencies {
    /// A panel that is cancelled, a drawing that does nothing, and nothing to show.
    static var declining: ShelfPDFMaker.Dependencies {
        ShelfPDFMaker.Dependencies(choose: { _ in nil }, render: { _, _, _, _ in }, words: { _ in nil }, reveal: { _ in },
                                   now: { Date() }, calendar: .current, locale: .current)
    }
}

private let zone = TimeZone(secondsFromGMT: -4 * 3600)!
private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// 22 October 2026, 9:12 in the zone four hours behind UTC.
private let now = Date(timeIntervalSince1970: 1_792_674_720)

private func item(_ file: String) -> ShelfItem {
    let stem = (file as NSString).deletingPathExtension
    let record = KeptRecord(
        name: stem, keptAt: now, projectID: "p", projectName: "Assay development", sessionID: "s", sessionTitle: "Plate reader QC",
        figure: KeptFile(path: file, role: .figure, artifact: "a", version: "v-\(file)", index: 1, of: nil, sha256: nil, bytes: 4_096),
        files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0")
    let result = KeptResult(folder: URL(fileURLWithPath: "/tmp/kept/Assay development/\(stem)", isDirectory: true), collection: "Assay development",
                            record: record, text: KeptText(legend: "", claudeSaid: "Plate 7 is the low bar.", attribution: "From Claude\u{2019}s answer.", origin: ""))
    return ShelfRules.items(from: [result])[0]
}

/// What the fakes were asked, and what they answer.
@MainActor
private final class Rig {
    var destination: URL? = URL(fileURLWithPath: "/tmp/Downloads/Lab meeting 2026-10-22.pdf", isDirectory: false)
    var failure: Error?
    var holding = false
    var reads: [URL: String] = [:]

    private(set) var offered: [String] = []
    private(set) var rendered: [(pages: [ShelfPDFPage], url: URL, title: String)] = []
    private(set) var revealed: [URL] = []
    private(set) var asked: [URL] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var reported: (@Sendable (Int) -> Void)?

    func release() {
        holding = false
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }

    /// Tells the command that `done` pages are drawn, as the drawing does while it runs.
    func report(_ done: Int) { reported?(done) }

    func record(_ pages: [ShelfPDFPage], _ url: URL, _ title: String, _ progress: @escaping @Sendable (Int) -> Void) async throws {
        rendered.append((pages, url, title))
        reported = progress
        if holding { await withCheckedContinuation { waiters.append($0) } }
        if let failure { throw failure }
    }

    var maker: ShelfPDFMaker {
        ShelfPDFMaker(dependencies: ShelfPDFMaker.Dependencies(
            choose: { [self] name in offered.append(name); return destination },
            render: { [self] pages, url, title, progress in try await record(pages, url, title, progress) },
            words: { [self] url in asked.append(url); return reads[url] },
            reveal: { [self] in revealed.append($0) },
            now: { now }, calendar: calendar, locale: Locale(identifier: "en_US")))
    }
}

@MainActor
struct ShelfPDFCommandTests {
    private func tell() -> (say: @MainActor (String) -> Void, said: () -> [String]) {
        let box = Said()
        return ({ box.all.append($0) }, { box.all })
    }

    @MainActor private final class Said { var all: [String] = [] }

    @Test func thePanelIsOfferedTheDaysNameAndTheFileIsShownInFinderWhenItIsMade() async {
        let rig = Rig()
        let (say, said) = tell()
        let maker = rig.maker
        await maker.make([item("a.png"), item("b.csv")], tell: say)
        #expect(rig.offered == ["Lab meeting 2026-10-22.pdf"])
        #expect(rig.rendered.count == 1)
        #expect(rig.rendered[0].url == rig.destination)
        #expect(rig.rendered[0].title == "Lab meeting 2026-10-22")
        #expect(rig.revealed == [rig.destination!])
        #expect(said().isEmpty && maker.phase == .idle && !maker.isMaking)
    }

    @Test func eachItemIsAPageInTheOrderGivenWithItsOwnWordsAndSource() async {
        let rig = Rig()
        await rig.maker.make([item("b.csv"), item("a.png")], tell: { _ in })
        let pages = rig.rendered[0].pages
        #expect(pages.map(\.fileName) == ["b.csv", "a.png"])
        #expect(pages.map(\.legend) == ["Plate 7 is the low bar.", "Plate 7 is the low bar."])
        #expect(pages[0].source == "Plate reader QC \u{00B7} Assay development \u{00B7} 22 Oct 2026")
        if case .image = pages[1].picture {} else { Issue.record("a figure should be a picture") }
        if case .tile = pages[0].picture {} else { Issue.record("a table should be a tile") }
    }

    @Test func onlyMarkdownAndTextFilesAreReadAndTheirWordsGoOnTheirPages() async {
        let rig = Rig()
        let note = item("notes.md"), table = item("b.csv"), figure = item("a.png"), plain = item("log.txt")
        rig.reads[note.fileURL] = "# Notes\n\nEleven plates pass."
        rig.reads[table.fileURL] = "plate,z\n1,0.8"
        await rig.maker.make([figure, note, table, plain], tell: { _ in })
        #expect(Set(rig.asked) == [note.fileURL, plain.fileURL])
        let pages = rig.rendered[0].pages
        #expect(pages[1].picture == .text([.heading("Notes"), .paragraph("Eleven plates pass.")]))
        // A table is a tile, a text file nobody could read a tile.
        #expect(pages[2].picture == .tile && pages[3].picture == .tile)
    }

    @Test func cancellingThePanelDoesNothingAtAllAndSaysNothing() async {
        let rig = Rig()
        rig.destination = nil
        let (say, said) = tell()
        let maker = rig.maker
        await maker.make([item("a.png")], tell: say)
        #expect(rig.offered.count == 1 && rig.rendered.isEmpty && rig.revealed.isEmpty && rig.asked.isEmpty)
        #expect(said().isEmpty && maker.phase == .idle)
    }

    @Test func nothingPickedAsksNothingAndSaysSo() async {
        let rig = Rig()
        let (say, said) = tell()
        await rig.maker.make([], tell: say)
        #expect(rig.offered.isEmpty && rig.rendered.isEmpty)
        #expect(said() == [ShelfPDFRules.nothingChosen])
    }

    @Test func aFileThatCantBeReadIsOneSentenceAndNothingIsShown() async {
        let rig = Rig()
        rig.failure = ShelfPDF.Failure.unreadable("a.png")
        let (say, said) = tell()
        let maker = rig.maker
        await maker.make([item("a.png")], tell: say)
        #expect(said() == ["Couldn\u{2019}t read a.png, which may have been moved out of the Shelf folder."])
        #expect(rig.revealed.isEmpty && maker.phase == .idle)
    }

    @Test func aPDFThatCantBeSavedNamesTheFolderItWasToGoIn() async {
        let rig = Rig()
        rig.failure = ShelfPDF.Failure.cantWrite
        let (say, said) = tell()
        await rig.maker.make([item("a.png")], tell: say)
        #expect(said() == ["Couldn\u{2019}t save the PDF to Downloads, which may be read-only or full."])
        #expect(rig.revealed.isEmpty)
        // Any other failure says the same.
        rig.failure = CocoaError(.fileWriteOutOfSpace)
        let again = tell()
        await rig.maker.make([item("a.png")], tell: again.say)
        #expect(again.said() == ["Couldn\u{2019}t save the PDF to Downloads, which may be read-only or full."])
        #expect(ShelfPDFMaker.folderName(of: URL(fileURLWithPath: "/x.pdf", isDirectory: false)) == "that folder")
    }

    @Test func onePDFIsMadeAtATimeAndTheProgressIsShownWhileItIs() async throws {
        let rig = Rig()
        rig.holding = true
        let maker = rig.maker
        let first = Task { await maker.make([item("a.png"), item("b.png"), item("c.png")], tell: { _ in }) }
        for _ in 0..<200 where !maker.isMaking || rig.rendered.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(maker.phase == .making(done: 0, total: 3))
        rig.report(2)
        for _ in 0..<200 where maker.phase != .making(done: 2, total: 3) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(maker.phase == .making(done: 2, total: 3))
        // A second ask meanwhile does nothing: not even the panel.
        await maker.make([item("d.png")], tell: { _ in })
        #expect(rig.offered.count == 1 && rig.rendered.count == 1)
        rig.release()
        await first.value
        #expect(maker.phase == .idle && rig.revealed.count == 1)
        // A late report doesn't bring the progress back.
        rig.report(3)
        try await Task.sleep(for: .milliseconds(50))
        #expect(maker.phase == .idle)
    }

    @Test func theFolderNameIsTheOneTheFileWasToGoIn() {
        #expect(ShelfPDFMaker.folderName(of: URL(fileURLWithPath: "/Volumes/Work/Downloads/x.pdf")) == "Downloads")
        #expect(ShelfPDFMaker.folderName(of: URL(fileURLWithPath: "/tmp/Lab meetings/x.pdf")) == "Lab meetings")
    }
}
