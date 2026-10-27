// CompareModelTests.swift — what the Compare window holds and when
// (Kept/CompareModel.swift), on a disk in memory that holds a read or the text
// changes until the test lets them go: a stale answer never reaches the current
// comparison (a rescan's reread, a later Compare, a close); Swap moves whole
// sides, provenance with picture, even with a read still out; a rescan that
// finds a file changed reads the pair again together and says so; a side that
// can't be read says why and the pair is never "No text changes"; a file iCloud
// has put away is never read; Fit, linked and unlinked zoom, and Wipe only for
// pictures of one size. Then on a real Kept folder: the pictures and text read
// through the disk layer, and not one byte or date of a source file changed.
import AppKit
import Combine
import Foundation
import Testing
@testable import Bench

@MainActor
struct CompareModelTests {
    private func gradient(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { (UInt8(x % 256), UInt8(y % 256), 90) }

    // MARK: Stale answers

    @Test func aRereadsTextChangesArriveAndTheOldPairsNeverReplaceThem() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("qc_notes.md"), b = CompareFixtures.item("qc_notes_revised.md", session: "Assay development QC")
        disk.put("# Plate reader QC\nEleven plates pass.\n", at: a.fileURL)
        disk.put("# Plate reader QC\nTwelve plates pass.\n", at: b.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        disk.holdDiffs = 1
        model.compare(a, b)
        let first = model.loadingTask
        #expect(await disk.until { disk.holdingDiffs == 1 })
        // The left file changes; the Shelf is read again and the pair with it, while the first pair's changes are still out.
        disk.put("# Plate reader QC\nTen plates pass.\n", at: a.fileURL)
        model.recheck()
        await model.settle()
        let fresh = try CompareDiff.compare("# Plate reader QC\nTen plates pass.\n", "# Plate reader QC\nTwelve plates pass.\n")
        #expect(model.outcome == fresh)
        // The first pair's answer, old A against B, arrives last: it is dropped.
        disk.releaseDiffs()
        await first?.value
        #expect(model.outcome == fresh)
        #expect(model.sides[0].content == .text("# Plate reader QC\nTen plates pass.\n"))
        #expect(model.note == "\u{201C}qc_notes.md\u{201D} changed on disk, so both sides were read again.")
    }

    @Test func aReadFromBeforeALaterCompareNeverReachesIt() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("qc_notes.md"), b = CompareFixtures.item("qc_notes_revised.md")
        disk.put("first\n", at: a.fileURL)
        disk.put("second\n", at: b.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        disk.holdReads = [a.fileURL.path]
        model.compare(a, b)
        let first = model.loadingTask
        #expect(await disk.until { disk.isHolding(a.fileURL) })
        // The file changes and the same pair is compared again: read at once, and shown.
        disk.put("first, edited\n", at: a.fileURL)
        model.compare(a, b)
        await model.settle()
        #expect(model.sides[0].content == .text("first, edited\n"))
        let generation = model.generation
        // The first read, of the old bytes, comes back last: nothing changes, not even a note or another read.
        disk.release(a.fileURL)
        await first?.value
        await model.settle()
        #expect(model.sides[0].content == .text("first, edited\n"))
        #expect(model.note == nil)
        #expect(model.generation == generation)
    }

    @Test func closingDropsEverythingStillOut() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("a.png"), b = CompareFixtures.item("b.png")
        disk.put(CompareFixtures.png(width: 40, height: 30, colour: gradient), at: a.fileURL)
        disk.put(CompareFixtures.png(width: 40, height: 30, colour: gradient), at: b.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        disk.holdReads = [a.fileURL.path]
        model.compare(a, b)
        let first = model.loadingTask
        #expect(await disk.until { disk.isHolding(a.fileURL) })
        model.close()
        disk.release(a.fileURL)
        await first?.value
        #expect(model.sides.isEmpty && model.kind == nil && model.outcome == nil)
        #expect(!disk.readLog.contains("b.png"))
    }

    // MARK: Swap

    @Test func swapMovesWholeSidesAndALateReadLandsOnItsOwnSide() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC", version: 2)
        let b = CompareFixtures.item("plate_7_heatmap.png", session: "Assay development", version: 5)
        disk.put(CompareFixtures.png(width: 48, height: 32, colour: gradient), at: a.fileURL)
        disk.put(CompareFixtures.png(width: 30, height: 20, colour: gradient), at: b.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        disk.holdReads = [b.fileURL.path]
        model.compare(a, b)
        #expect(await disk.until { disk.isHolding(b.fileURL) })
        #expect(model.sides[0].content.image?.source == CGSize(width: 48, height: 32))
        // Swapped while the right side's read is still out.
        model.swap()
        #expect(model.sides.map(\.fileName) == ["plate_7_heatmap.png", "z_prime_by_plate.png"])
        disk.release(b.fileURL)
        await model.settle()
        // Each side's file, its words and its picture are still one.
        #expect(model.sides[0].fileName == "plate_7_heatmap.png")
        #expect(model.sides[0].sourceLine == "Assay development \u{00B7} version 5")
        #expect(model.sides[0].content.image?.source == CGSize(width: 30, height: 20))
        #expect(model.sides[1].fileName == "z_prime_by_plate.png")
        #expect(model.sides[1].sourceLine == "Plate reader QC \u{00B7} version 2")
        #expect(model.sides[1].content.image?.source == CGSize(width: 48, height: 32))
        // And back.
        model.swap()
        #expect(model.sides[0].sourceLine == "Plate reader QC \u{00B7} version 2")
        #expect(model.sides[0].content.image?.source == CGSize(width: 48, height: 32))
    }

    @Test func swapShowsTheTextChangesFromTheOtherSideWithoutReadingAgain() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("qc_notes.md"), b = CompareFixtures.item("qc_notes_revised.md")
        disk.put("a\nb\nc\n", at: a.fileURL)
        disk.put("a\nB\nc\nd\n", at: b.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        model.compare(a, b)
        await model.settle()
        let reads = disk.readLog.count, diffs = disk.diffCalls
        #expect(model.document?.marks.map(\.kind) == [.removed, .added, .added])
        model.swap()
        #expect(model.document?.marks.map(\.kind) == [.removed, .added, .removed])
        #expect(model.outcome == (try CompareDiff.compare("a\nb\nc\n", "a\nB\nc\nd\n")).inverted())
        #expect(disk.readLog.count == reads && disk.diffCalls == diffs)
    }

    @Test func swapKeepsTheLinkedViewAndEachPanesOwnViewTravelsWithIt() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("a.png"), b = CompareFixtures.item("b.png")
        disk.put(CompareFixtures.png(width: 400, height: 300, colour: gradient), at: a.fileURL)
        disk.put(CompareFixtures.png(width: 800, height: 400, colour: gradient), at: b.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        model.compare(a, b)
        await model.settle()
        let view = CGSize(width: 300, height: 300)
        model.zoom(a.id, by: 2, at: CGPoint(x: 60, y: 90), view: view)
        let linked = model.viewport(for: a.id)
        #expect(model.viewport(for: b.id) == linked && linked.scale == 2)
        model.swap()
        #expect(model.viewport(for: a.id) == linked && model.viewport(for: b.id) == linked)
        // Unlinked, each keeps its own, and they go with their sides.
        model.setLinked(false)
        model.zoom(b.id, by: 3, view: view)
        let ownB = model.viewport(for: b.id)
        #expect(ownB.scale == 6 && model.viewport(for: a.id) == linked)
        model.swap()
        #expect(model.viewport(for: b.id) == ownB && model.viewport(for: a.id) == linked)
        // Fit puts both back.
        model.fit()
        #expect(model.viewport(for: a.id) == .fit && model.viewport(for: b.id) == .fit)
        // Linked again, both follow the left picture (b, after the swaps).
        model.zoom(model.sides[0].id, by: 2, view: view)
        let left = model.viewport(for: model.sides[0].id)
        model.setLinked(true)
        #expect(model.viewport(for: a.id) == left && model.viewport(for: b.id) == left)
    }

    // MARK: A rescan

    @Test func aChangedFileOnARescanReadsThePairAgainTogether() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("qc_notes.md"), b = CompareFixtures.item("qc_notes_revised.md")
        disk.put("one\ntwo\n", at: a.fileURL)
        disk.put("one\nthree\n", at: b.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        model.compare(a, b)
        await model.settle()
        // A rescan with nothing changed reads nothing.
        model.recheck()
        await model.settle()
        #expect(disk.readLog == ["qc_notes.md", "qc_notes_revised.md"] && model.note == nil)
        // The right file changes; while the pair is read again, nothing of the old comparison shows.
        disk.put("one\nfour\n", at: b.fileURL)
        disk.holdReads = [a.fileURL.path]
        model.recheck()
        #expect(await disk.until { disk.isHolding(a.fileURL) })
        #expect(model.outcome == nil && model.document == nil)
        #expect(model.sides.allSatisfy { $0.content == .reading })
        disk.release(a.fileURL)
        await model.settle()
        #expect(model.outcome == (try CompareDiff.compare("one\ntwo\n", "one\nfour\n")))
        #expect(model.note == "\u{201C}qc_notes_revised.md\u{201D} changed on disk, so both sides were read again.")
        #expect(disk.readLog == ["qc_notes.md", "qc_notes_revised.md", "qc_notes.md", "qc_notes_revised.md"])
    }

    @Test func aFileChangedWhileReadIsReadAgainAndOneThatKeepsChangingSaysSo() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("qc_notes.md"), b = CompareFixtures.item("qc_notes_revised.md")
        disk.put("one\n", at: a.fileURL)
        disk.put("two\n", at: b.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        disk.holdReads = [a.fileURL.path]
        model.compare(a, b)
        #expect(await disk.until { disk.isHolding(a.fileURL) })
        disk.put("one, edited\n", at: a.fileURL)
        disk.release(a.fileURL)
        await model.settle()
        #expect(model.sides[0].content == .text("one, edited\n"))
        #expect(model.note == "\u{201C}qc_notes.md\u{201D} changed while Capsid read it, so both sides were read again.")
        // Changing at every read: said so, and the pair is not compared.
        let changing = CompareModel(reader: CompareReader(
            inspect: { _ in KeptFileFacts(modified: Date(), size: 4, putAway: false) },
            read: { _, _ in Data("text".utf8) }, decode: { CompareImages.decode($0) },
            diff: { left, right in try? CompareDiff.compare(left, right) }), announce: { _ in })
        changing.compare(a, b)
        await changing.settle()
        #expect(changing.sides.allSatisfy { $0.content == .problem(.changing) })
        #expect(changing.textState == .unavailable && changing.outcome == nil)
    }

    // MARK: Sides that can't be read

    @Test func aSideThatCantBeReadSaysWhyAndThePairIsNeverNoTextChanges() async throws {
        let ok = CompareFixtures.item("qc_notes.md")
        let cases: [(String, @MainActor (CompareFakeDisk, URL) -> Void, CompareProblem)] = [
            ("gone.md", { _, _ in }, .missing),
            ("away.md", { disk, url in disk.put(Data("same\n".utf8), at: url, putAway: true) }, .inICloud),
            ("big.md", { disk, url in disk.put(Data(repeating: 0x61, count: ShelfDocumentReading.byteLimit + 1), at: url) },
             .tooLarge(bytes: ShelfDocumentReading.byteLimit + 1, limit: ShelfDocumentReading.byteLimit)),
            ("binary.md", { disk, url in disk.put(Data([0x61, 0x00, 0x62]), at: url) }, .notText),
            ("latin.txt", { disk, url in disk.put(Data([0x63, 0x61, 0x66, 0xE9]), at: url) }, .notText),
        ]
        for (name, setUp, problem) in cases {
            let disk = CompareFakeDisk()
            let other = CompareFixtures.item(name)
            disk.put("same\n", at: ok.fileURL)
            setUp(disk, other.fileURL)
            let model = CompareModel(reader: disk.reader, announce: { _ in })
            model.compare(ok, other)
            await model.settle()
            #expect(model.sides[1].content == .problem(problem), "\(name)")
            #expect(model.textState == .unavailable && model.outcome == nil && model.document == nil, "\(name)")
            #expect(disk.diffCalls == 0, "\(name)")
            // Never fetched to be compared.
            if problem == .inICloud || problem == .missing { #expect(!disk.readLog.contains(name)) }
        }
    }

    @Test func picturesThatCantBeReadSayWhyOnTheirOwnSide() async throws {
        let disk = CompareFakeDisk()
        let good = CompareFixtures.item("z_prime_by_plate.png"), bad = CompareFixtures.item("broken.png")
        let big = CompareFixtures.item("huge.tiff"), away = CompareFixtures.item("away.png")
        disk.put(CompareFixtures.png(width: 48, height: 32, colour: gradient), at: good.fileURL)
        disk.put(Data("not a picture".utf8), at: bad.fileURL)
        disk.put(Data(repeating: 1, count: CompareImages.byteLimit + 1), at: big.fileURL)
        disk.put(CompareFixtures.png(width: 48, height: 32, colour: gradient), at: away.fileURL, putAway: true)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        for (other, problem) in [(bad, CompareProblem.notAPicture), (big, .tooLarge(bytes: CompareImages.byteLimit + 1, limit: CompareImages.byteLimit)),
                                 (away, .inICloud)] {
            model.compare(good, other)
            await model.settle()
            #expect(model.sides[0].content.image != nil)
            #expect(model.sides[1].content == .problem(problem))
            #expect(!model.canWipe)
        }
        #expect(!disk.readLog.contains("away.png") && !disk.readLog.contains("huge.tiff"))
        #expect(CompareProblem.inICloud.sentence("away.png") == "\u{201C}away.png\u{201D} is in iCloud and not on this Mac. Capsid doesn\u{2019}t download it to compare.")
        #expect(CompareProblem.tooLarge(bytes: 300_000, limit: 262_144).sentence("qc.md").contains("more than the"))
    }

    @Test func emptyTextsCompareAsTextAndTheSameTextIsNoChanges() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("empty.md"), b = CompareFixtures.item("also_empty.txt"), c = CompareFixtures.item("qc_notes.md")
        disk.put(Data(), at: a.fileURL)
        disk.put(Data(), at: b.fileURL)
        disk.put("\u{FEFF}Plate 7\r\n", at: c.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        model.compare(a, b)
        await model.settle()
        #expect(model.outcome == .identical)
        model.compare(a, c)
        await model.settle()
        #expect(model.sides[1].content == .text("Plate 7\n"))
        #expect(model.document?.marks.map(\.kind) == [.added])
    }

    // MARK: Pictures

    @Test func wipeIsOfferedOnlyForPicturesOfOneUprightSize() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("a.png"), same = CompareFixtures.item("b.jpg"), other = CompareFixtures.item("c.png")
        disk.put(CompareFixtures.png(width: 30, height: 40, colour: gradient), at: a.fileURL)
        // Stored 40 × 30, turned upright to 30 × 40.
        disk.put(CompareFixtures.jpeg(width: 40, height: 30, orientation: 6, colour: gradient), at: same.fileURL)
        disk.put(CompareFixtures.png(width: 40, height: 30, colour: gradient), at: other.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })
        model.compare(a, same)
        await model.settle()
        #expect(model.canWipe)
        model.setWiping(true)
        #expect(model.wiping)
        model.moveDivider(by: 3)
        #expect(abs(model.wipeFraction - 0.65) < 1e-9)
        model.compare(a, other)
        #expect(!model.wiping && model.wipeFraction == 0.5)
        await model.settle()
        #expect(!model.canWipe)
        model.setWiping(true)
        #expect(!model.wiping)
    }

    @Test func previousAndNextChangeGoThroughTheChangesAndSayEach() async throws {
        let disk = CompareFakeDisk()
        let a = CompareFixtures.item("qc_notes.md"), b = CompareFixtures.item("qc_notes_revised.md")
        disk.put("1\n2\n3\n4\n5\n", at: a.fileURL)
        disk.put("1\nB\n3\n4\n5\n6\n", at: b.fileURL)
        @MainActor final class Said { var lines: [String] = [] }
        let said = Said()
        let model = CompareModel(reader: disk.reader, announce: { said.lines.append($0) })
        model.compare(a, b)
        await model.settle()
        #expect(model.changeCount == 2 && !model.canGoToPreviousChange && model.canGoToNextChange)
        model.nextChange()
        model.nextChange()
        #expect(model.changeIndex == 1 && model.jumps == 2 && !model.canGoToNextChange)
        model.previousChange()
        #expect(model.changeIndex == 0)
        #expect(said.lines == ["Change 1 of 2. Removed 1 line, added 1.", "Change 2 of 2. Added 1 line.", "Change 1 of 2. Removed 1 line, added 1."])
    }

    // MARK: A real Kept folder

    @Test func theLiveReaderReadsThroughTheDiskLayerAndChangesNoSourceFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compare-live-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let items = ShelfRules.items(from: index.results)
        func named(_ file: String) -> ShelfItem { items.first { $0.fileName == file }! }
        let pictures = (named("z_prime_by_plate.png"), named("plate_7_heatmap.png"))
        let texts = (named("qc_notes.md"), named("methods_draft.md"))
        let files = [pictures.0, pictures.1, texts.0, texts.1].map(\.fileURL)
        func snapshot() throws -> [Data] {
            try files.map { url in
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                return try Data(contentsOf: url) + Data("\(date) \(attributes[.posixPermissions] ?? 0)".utf8)
            }
        }
        let before = try snapshot()
        let model = CompareModel(reader: .live(disk: disk), changes: index.$results.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                                 announce: { _ in })
        model.compare(pictures.0, pictures.1)
        await model.settle()
        #expect(model.sides.allSatisfy { $0.content.image != nil })
        #expect(model.canWipe)
        model.swap()
        model.setWiping(true)
        model.compare(texts.0, texts.1)
        await model.settle()
        #expect(model.outcome == .identical)
        // A rescan with nothing changed.
        await index.refreshAndWait()
        await model.settle()
        #expect(model.note == nil)
        model.close()
        #expect(try snapshot() == before)
        // Nothing new beside them either.
        for url in files {
            let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).sorted()
            #expect(names == [url.lastPathComponent, "README.md"].sorted())
        }
    }
}
