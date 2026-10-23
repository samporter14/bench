// ShelfRulesTests.swift — the shelf's rules (Kept/ShelfRules.swift), pure, on
// made-up folders: which chip a file is under, how kept folders become items
// (one for each figure version, the folder with data and code shown), what a
// project, a kind and a search leave, the words on a card and in the detail,
// and the README an add writes, word for word.
import Foundation
import Testing
@testable import Bench

private let zone = TimeZone(secondsFromGMT: -4 * 3600)!
private let english = Locale(identifier: "en_US")
private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// 22 October 2026, 9:12 in the zone four hours behind UTC.
private let now = Date(timeIntervalSince1970: 1_792_674_720)
private func ago(days: Double = 0, hours: Double = 0, minutes: Double = 0) -> Date {
    now.addingTimeInterval(-(days * 86_400 + hours * 3_600 + minutes * 60))
}

private func result(_ file: String = "z_prime_by_plate.png", name: String? = nil, version: String? = "v-1", collection: String = "Assay development",
                    session: String = "Plate reader QC", project: String = "Assay development", at keptAt: Date = now, withData: Bool = false,
                    legend: String = "", said: String = "Plate 7 is the low bar.", question: String? = nil, answerAt: Date? = nil,
                    index: Int? = 3, of: Int? = nil, folder: String? = nil) -> KeptResult {
    let stem = (file as NSString).deletingPathExtension
    let folderName = folder ?? name ?? stem
    let record = KeptRecord(
        name: name ?? stem, keptAt: keptAt, projectID: "p", projectName: project, sessionID: "s", sessionTitle: session,
        figure: KeptFile(path: file, role: .figure, artifact: "a", version: version, index: index, of: of, sha256: nil, bytes: 10),
        files: withData ? [KeptFile(path: "data/x.csv", role: .data, bytes: 4)] : [], missing: [],
        claudeScience: "0.1.70", capsid: "1.0", sourceRow: 12, question: question, answerAt: answerAt)
    return KeptResult(folder: URL(fileURLWithPath: "/tmp/kept/\(collection)/\(folderName)", isDirectory: true), collection: collection,
                      record: record, text: KeptText(legend: legend, claudeSaid: said, attribution: "From Claude’s answer.", origin: ""))
}

struct ShelfKindTests {
    @Test func aFileIsAFigureATableOrADocumentByItsName() {
        for name in ["a.png", "a.PNG", "a.jpg", "a.jpeg", "a.gif", "a.webp", "a.svg", "a.tif", "a.tiff", "a.heic"] {
            #expect(ShelfKind.classify(fileName: name) == .figure, "\(name)")
        }
        for name in ["a.csv", "a.tsv", "a.xlsx", "a.XLSX", "a.xls", "a.ods", "a.numbers", "a.parquet"] {
            #expect(ShelfKind.classify(fileName: name) == .table, "\(name)")
        }
        // Everything a person writes with, and anything else, is a document.
        for name in ["qc_notes.md", "a.txt", "a.pdf", "report.html", "a.docx", "a.ipynb", "a.py", "a.json", "README", "archive.tar.gz"] {
            #expect(ShelfKind.classify(fileName: name) == .document, "\(name)")
        }
        #expect(ShelfKind.classify(fileName: "figure.png.md") == .document)
        #expect(ShelfKind.classify(fileName: "table.csv.png") == .figure)
    }

    @Test func theChipsAreThreeAndSaidInTheBoardsWords() {
        #expect(ShelfKind.allCases.map(\.chip) == ["Figures", "Documents", "Tables"])
        #expect(ShelfKind.allCases.map(\.noun) == ["figures", "documents", "tables"])
        let counts = ShelfRules.Counts(all: 12, figures: 7, documents: 3, tables: 2)
        #expect(ShelfRules.chipLabel(nil, counts) == "All \u{00B7} 12")
        #expect(ShelfRules.chipLabel(.figure, counts) == "Figures \u{00B7} 7")
        #expect(ShelfRules.chipLabel(.document, counts) == "Documents \u{00B7} 3")
        #expect(ShelfRules.chipLabel(.table, counts) == "Tables \u{00B7} 2")
    }
}

struct ShelfItemsTests {
    @Test func oneItemForEachFigureVersionNewestFirst() {
        let items = ShelfRules.items(from: [
            result("a.png", version: "v-1", at: ago(minutes: 5)),
            result("b.png", version: "v-2", at: ago(minutes: 1)),
            result("c.md", version: "v-3", at: ago(days: 2)),
        ])
        #expect(items.map(\.fileName) == ["b.png", "a.png", "c.md"])
        #expect(items.map(\.kind) == [.figure, .figure, .document])
        #expect(items.allSatisfy { $0.others.isEmpty })
    }

    @Test func aFigureKeptAgainWithItsDataAndCodeIsOneItemAndTheRicherFolderIsShown() {
        let shelved = result("z.png", version: "v-9", at: ago(days: 1), folder: "z")
        let kept = result("z.png", name: "Fig 2B", version: "v-9", at: ago(minutes: 30), withData: true, folder: "Fig 2B")
        let later = result("z.png", version: "v-9", at: ago(minutes: 1), folder: "z 2026-10-22 0912")
        let items = ShelfRules.items(from: [later, shelved, kept])
        #expect(items.count == 1)
        let item = items[0]
        #expect(item.folder == kept.folder)
        #expect(item.others.map(\.folder) == [later.folder, shelved.folder])
        #expect(item.folders == [kept.folder, later.folder, shelved.folder])
        #expect(item.hasMore)
        #expect(item.contains(folder: shelved.folder) && !item.contains(folder: URL(fileURLWithPath: "/tmp/other")))
        // When is the newest of its folders.
        #expect(item.addedAt == later.record.keptAt)
    }

    @Test func twoShelvedFoldersOfOneVersionShowTheNewestAndTheChoiceNeverWobbles() {
        let a = result("z.png", version: "v-9", at: ago(days: 1), folder: "a")
        let b = result("z.png", version: "v-9", at: ago(days: 2), folder: "b")
        #expect(ShelfRules.items(from: [a, b]).first?.folder == a.folder)
        #expect(ShelfRules.items(from: [b, a]).first?.folder == a.folder)
        // The same time: by path.
        let c = result("z.png", version: "v-9", at: ago(days: 1), folder: "c")
        #expect(ShelfRules.items(from: [c, a]).first?.folder == a.folder)
        #expect(ShelfRules.items(from: [a, c]).first?.folder == a.folder)
    }

    @Test func aFolderWithNoVersionIsItsOwnItem() {
        let items = ShelfRules.items(from: [result("a.png", version: nil, folder: "one"), result("a.png", version: nil, folder: "two")])
        #expect(items.count == 2)
    }

    @Test func aLegendWrittenByHandIsMoreToShow() {
        #expect(ShelfRules.items(from: [result(legend: "Plate 3 was re-run.")])[0].hasMore)
        #expect(!ShelfRules.items(from: [result()])[0].hasMore)
    }

    @Test func aCardReadsTheFilesOwnNameUnlessTheKeepWasGivenOne() {
        #expect(ShelfRules.title(for: result("z_prime_by_plate.png").record) == "z_prime_by_plate.png")
        // A name taken: the date, then a number.
        #expect(ShelfRules.title(for: result("z_prime_by_plate.png", name: "z_prime_by_plate 2026-10-22 0912").record) == "z_prime_by_plate.png")
        #expect(ShelfRules.title(for: result("z_prime_by_plate.png", name: "z_prime_by_plate 2026-10-22 0912 2").record) == "z_prime_by_plate.png")
        // One a person named is what they named it.
        #expect(ShelfRules.title(for: result("z_prime.png", name: "Fig 2B \u{00B7} Z\u{2032} by plate").record) == "Fig 2B \u{00B7} Z\u{2032} by plate")
        #expect(ShelfRules.title(for: result("z_prime.png", name: "z_prime and more").record) == "z_prime and more")
        // A file with no extension, and one with dots.
        #expect(ShelfRules.title(for: result("notes", name: "notes").record) == "notes")
        #expect(ShelfRules.title(for: result("plate.7.heatmap.png", name: "plate.7.heatmap").record) == "plate.7.heatmap.png")
    }
}

struct ShelfFilterTests {
    private let items = ShelfRules.items(from: [
        result("z_prime_by_plate.png", version: "v-1", collection: "Assay development", session: "Plate reader QC", at: ago(minutes: 1)),
        result("plate_7_heatmap.png", version: "v-2", collection: "Assay development", session: "Plate reader QC", at: ago(minutes: 2),
               said: "The edge effect is in column 12."),
        result("qc_notes.md", version: "v-3", collection: "Assay development", session: "Plate reader QC", at: ago(minutes: 3),
               legend: "Notes for the notebook."),
        result("receptors.xlsx", version: "v-4", collection: "Receptor biology", session: "ER-phagy receptors", project: "Receptor biology",
               at: ago(days: 3), said: "Eleven receptors carry an LIR motif.", question: "Which receptors have an LIR motif?"),
        result("knockdown_blot.png", version: "v-5", collection: "Knockdown validation", session: "Western blot quantification",
               project: "Knockdown validation", at: ago(days: 5)),
    ])

    @Test func nothingChosenLeavesEverything() {
        #expect(ShelfRules.matching(items, project: nil, query: "").count == 5)
        #expect(ShelfRules.matching(items, project: nil, query: "   ").count == 5)
    }

    @Test func aProjectLeavesItsOwnCollection() {
        #expect(ShelfRules.matching(items, project: "Assay development", query: "").map(\.fileName)
            == ["z_prime_by_plate.png", "plate_7_heatmap.png", "qc_notes.md"])
        #expect(ShelfRules.matching(items, project: "Receptor biology", query: "").map(\.fileName) == ["receptors.xlsx"])
        #expect(ShelfRules.matching(items, project: "Nowhere", query: "").isEmpty)
    }

    @Test func aSearchCoversNamesSessionsLegendsClaudesWordsAndQuestions() {
        func found(_ query: String, project: String? = nil) -> [String] { ShelfRules.matching(items, project: project, query: query).map(\.fileName) }
        #expect(found("heatmap") == ["plate_7_heatmap.png"])
        #expect(found("HEATMAP") == ["plate_7_heatmap.png"])
        #expect(found("er-phagy") == ["receptors.xlsx"])
        #expect(found("notebook") == ["qc_notes.md"])
        #expect(found("column 12") == ["plate_7_heatmap.png"])
        #expect(found("LIR motif") == ["receptors.xlsx"])
        #expect(found("blot") == ["knockdown_blot.png"])
        // Every word has to be somewhere in it.
        #expect(found("plate qc notebook") == ["qc_notes.md"])
        #expect(found("plate zebrafish").isEmpty)
        // And a project narrows it.
        #expect(found("plate", project: "Receptor biology").isEmpty)
        #expect(found("plate", project: "Assay development").count == 3)
    }

    @Test func theChipsCountWhatTheProjectAndTheSearchLeave() {
        #expect(ShelfRules.counts(of: items) == ShelfRules.Counts(all: 5, figures: 3, documents: 1, tables: 1))
        let scoped = ShelfRules.matching(items, project: "Assay development", query: "")
        #expect(ShelfRules.counts(of: scoped) == ShelfRules.Counts(all: 3, figures: 2, documents: 1, tables: 0))
        #expect(ShelfRules.counts(of: scoped).of(nil) == 3)
        #expect(ShelfRules.counts(of: scoped).of(.figure) == 2)
        #expect(ShelfRules.counts(of: scoped).of(.table) == 0)
        #expect(ShelfRules.items(items, of: .figure).map(\.fileName) == ["z_prime_by_plate.png", "plate_7_heatmap.png", "knockdown_blot.png"])
        #expect(ShelfRules.items(items, of: nil).count == 5)
        #expect(ShelfRules.items(items, of: .table).map(\.fileName) == ["receptors.xlsx"])
    }
}

struct ShelfWordsTests {
    private func item(_ result: KeptResult) -> ShelfItem { ShelfRules.items(from: [result])[0] }

    @MainActor @Test func keepFromTheShelfPicksTheItemsOwnVersion() throws {
        let subject = try #require(ShelfActions.keepSubject(item(result(at: ago(minutes: 25)))))
        #expect(subject.selectsItsVersion)
    }

    @Test func aCardNamesTheSessionAndWhenItWasShelved() {
        func caption(_ added: Date) -> String {
            ShelfRules.caption(for: item(result(at: added)), now: now, calendar: calendar, locale: english).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(caption(ago(minutes: 25)) == "Plate reader QC \u{00B7} 8:47 AM")
        #expect(caption(ago(hours: 5)) == "Plate reader QC \u{00B7} 4:12 AM")
        #expect(caption(ago(days: 1)) == "Plate reader QC \u{00B7} Yesterday")
        #expect(caption(ago(days: 3)) == "Plate reader QC \u{00B7} Mon")
        #expect(caption(ago(days: 6)) == "Plate reader QC \u{00B7} Fri")
        #expect(caption(ago(days: 7)) == "Plate reader QC \u{00B7} Oct 15")
        #expect(caption(ago(days: 40)) == "Plate reader QC \u{00B7} Sep 12")
        #expect(caption(ago(days: 400)) == "Plate reader QC \u{00B7} Sep 17, 2025")
    }

    /// Board 12's line: "Session · Project · version N · time", the time Claude answered as a card says it.
    @Test func theDetailSaysWhereItCameFrom() {
        func line(_ result: KeptResult) -> String {
            ShelfRules.sourceLine(for: item(result), now: now, calendar: calendar, locale: english).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(line(result(answerAt: ago(minutes: 25))) == "Plate reader QC \u{00B7} Assay development \u{00B7} version 3 \u{00B7} 8:47 AM")
        // Another day: the day, not the time of an hour that wasn't today.
        #expect(line(result(answerAt: ago(days: 3))) == "Plate reader QC \u{00B7} Assay development \u{00B7} version 3 \u{00B7} Mon")
        #expect(line(result(answerAt: ago(days: 1))) == "Plate reader QC \u{00B7} Assay development \u{00B7} version 3 \u{00B7} Yesterday")
        #expect(line(result(answerAt: ago(days: 12))) == "Plate reader QC \u{00B7} Assay development \u{00B7} version 3 \u{00B7} Oct 10")
        // No time known (kept before the shelf), "version 3 of 4".
        #expect(line(result(index: 3, of: 4)) == "Plate reader QC \u{00B7} Assay development \u{00B7} version 3 of 4")
        // No words kept: no answer to give the time of.
        #expect(line(result(said: "", answerAt: ago(minutes: 25))) == "Plate reader QC \u{00B7} Assay development \u{00B7} version 3")
        // No version number to give, no project.
        #expect(line(result(index: nil)) == "Plate reader QC \u{00B7} Assay development")
        #expect(line(result(project: "", answerAt: ago(minutes: 25))) == "Plate reader QC \u{00B7} version 3 \u{00B7} 8:47 AM")
    }

    /// The line has no room for it, so a note under Claude's words says these are the session's last.
    @Test func theLastAnswerIsSaidToBeTheLast() {
        var last = result(answerAt: ago(minutes: 25))
        last = KeptResult(folder: last.folder, collection: last.collection, record: last.record,
                          text: KeptText(legend: "", claudeSaid: "Words.",
                                         attribution: "From Claude\u{2019}s last answer in the session at 8:47 AM on 22 October 2026. The answer that shows this version wasn\u{2019}t found.",
                                         origin: ""))
        #expect(ShelfRules.isLastAnswer(last.text))
        #expect(ShelfRules.sourceLine(for: item(last), now: now, calendar: calendar, locale: english).replacingOccurrences(of: "\u{202F}", with: " ")
            == "Plate reader QC \u{00B7} Assay development \u{00B7} version 3 \u{00B7} 8:47 AM")
        #expect(ShelfRules.lastAnswerNote(for: item(last)) == "Claude\u{2019}s last answer in the session; the one that showed this wasn\u{2019}t found.")
        #expect(!ShelfRules.isLastAnswer(result().text))
        #expect(ShelfRules.lastAnswerNote(for: item(result())) == nil)
    }

    /// Board 12 shows the question in quotes, muted, without "You asked:".
    @Test func whatYouAskedIsOneLineAndOnlyWhenKnown() {
        #expect(ShelfRules.askedLine(for: item(result())) == nil)
        #expect(ShelfRules.askedLine(for: item(result(question: "  \n "))) == nil)
        #expect(ShelfRules.askedLine(for: item(result(question: "Plot Z\u{2032} by plate,\nand show me\n\n where plate 7 goes wrong.")))
            == "\u{201C}Plot Z\u{2032} by plate, and show me where plate 7 goes wrong.\u{201D}")
    }

    @Test func theEmptyStatesSayWhatToDo() {
        #expect(ShelfRules.emptyTitle == "Nothing on your shelf yet")
        #expect(ShelfRules.emptySentence == "Right-click a figure in a conversation and choose Add to Shelf.")
        #expect(ShelfRules.emptyKindTitle(.table) == "No tables on your shelf")
        #expect(ShelfRules.emptyKindTitle(.figure) == "No figures on your shelf")
        #expect(ShelfRules.removed("z.png") == "Moved z.png to the Trash.")
        #expect(ShelfRules.couldntRemove("z.png", "The folder didn't respond.") == "Couldn\u{2019}t move z.png to the Trash. The folder didn't respond.")
        #expect(ShelfRules.couldntRemove("z.png", nil) == "Couldn\u{2019}t move z.png to the Trash.")
    }
}

struct ShelfReadmeWordsTests {
    private let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000c1", projectID: "p-3", projectName: "Assay development",
                                        title: "Plate reader QC", state: .finished, updatedAt: now, startedAt: nil)
    private let figure = KeptFile(path: "z_prime_by_plate.png", role: .figure, artifact: "art_1", version: "ver_3", index: 3, of: nil,
                                  sha256: "aaaa", bytes: 86_016)

    private func readme(answer: ShelfRules.Answer?, row: Int?, question: String?) -> (record: KeptRecord, text: KeptText) {
        ShelfRules.readme(session: session, folderName: "z_prime_by_plate", figure: figure, answer: answer, row: row, question: question,
                          keptAt: now, claudeScience: "0.1.70", capsid: "1.0", timeZone: zone, locale: english)
    }

    @Test func theReadmeSaysWhereItCameFromInWords() throws {
        let answered = ShelfRules.Answer(text: "Plate 7 is the low bar.", at: ago(minutes: 25), isLast: false)
        let made = readme(answer: answered, row: 19, question: "Plot Z\u{2032} by plate, and show me where plate 7 goes wrong.")
        let markdown = KeptReadme.render(made.record, text: made.text, timeZone: zone, locale: english)
        #expect(markdown.contains("""
            ## Where it came from

            [Plate reader QC](bench://session?project=p-3&frame=00000000-0000-4000-8000-0000000000c1), in Assay development.
            From Claude’s answer at 8:47 AM on 22 October 2026, message 19 in the session’s history. You asked: “Plot Z′ by plate, and show me where plate 7 goes wrong.”
            Version 3 of z_prime_by_plate.png, put on your shelf on 22 October 2026 at 9:12 AM by Capsid 1.0, from Claude Science 0.1.70. The link opens the session in Capsid on a Mac that has it.

            """))
        #expect(markdown.contains("> Plate 7 is the low bar.\n\nFrom Claude’s answer at 8:47 AM on 22 October 2026.\n"))
        #expect(markdown.contains("figure: { file: \"z_prime_by_plate.png\", artifact: \"art_1\", version: \"ver_3\", index: 3, sha256: \"aaaa\", bytes: 86016 }\n"
            + "source_row: 19\nquestion: \"Plot Z′ by plate, and show me where plate 7 goes wrong.\"\nanswer_at: 2026-10-22T08:47:00-04:00\nfiles: []\n"))
        #expect(!markdown.contains("## Not copied"))
        // What it writes is what it reads back, byte for byte.
        let parsed = try #require(KeptReadme.parse(markdown))
        #expect(KeptReadme.render(parsed.record, text: parsed.text, timeZone: zone, locale: english) == markdown)
        #expect(parsed.record == made.record)
    }

    @Test func wordsThatAreCutSaySoInTheirAttributionAndNothingElseDoes() throws {
        let whole = ShelfRules.Answer(text: "Plate 7 is the low bar.", at: ago(minutes: 25), isLast: false)
        #expect(!readme(answer: whole, row: 19, question: nil).text.attribution.contains("cut"))
        var cut = whole
        cut.cut = true
        let made = readme(answer: cut, row: 19, question: nil)
        #expect(made.text.attribution
            == "From Claude\u{2019}s answer at 8:47 AM on 22 October 2026. The text is cut off: the rest couldn\u{2019}t be read.")
        #expect(KeptReadme.cutSentence == "The text is cut off: the rest couldn\u{2019}t be read.")
        // It is in the README under the words, and reads back as it was written.
        let markdown = KeptReadme.render(made.record, text: made.text, timeZone: zone, locale: english)
        #expect(markdown.contains("> Plate 7 is the low bar.\n\nFrom Claude\u{2019}s answer at 8:47 AM on 22 October 2026. The text is cut off: the rest couldn\u{2019}t be read.\n"))
        let parsed = try #require(KeptReadme.parse(markdown))
        #expect(KeptReadme.render(parsed.record, text: parsed.text, timeZone: zone, locale: english) == markdown)
        // The last answer in the session, which was read whole, never says it.
        let last = ShelfRules.Answer(text: "Words.", at: nil, isLast: true)
        #expect(!readme(answer: last, row: nil, question: nil).text.attribution.contains("cut off"))
    }

    @Test func withoutARowOrAQuestionTheSentencesSkipThem() {
        let answered = ShelfRules.Answer(text: "Words.", at: ago(minutes: 25), isLast: false)
        let made = readme(answer: answered, row: nil, question: nil)
        #expect(made.text.origin.contains("\nFrom Claude’s answer at 8:47 AM on 22 October 2026.\nVersion 3 of "))
        #expect(made.record.sourceRow == nil && made.record.question == nil)
        let blank = readme(answer: answered, row: 4, question: " \n ")
        #expect(blank.record.question == nil)
        #expect(blank.record.sourceRow == 4)
    }

    @Test func aQuestionIsFlattenedAndCutToFourHundredCharacters() {
        let long = String(repeating: "plate ", count: 200)
        let made = readme(answer: ShelfRules.Answer(text: "Words.", at: nil, isLast: false), row: 4, question: "First line\nsecond line\n" + long)
        let question = made.record.question ?? ""
        #expect(question.hasPrefix("First line second line plate"))
        #expect(question.count <= ShelfRules.questionLimit)
        #expect(!question.contains("\n"))
    }

    @Test func theLastAnswerStandsInAndTheReadmeSaysSoWithoutARow() {
        let last = ShelfRules.Answer(text: "Last words.", at: ago(minutes: 25), isLast: true)
        let made = readme(answer: last, row: 19, question: "A question")
        #expect(made.record.sourceRow == nil)
        #expect(made.text.attribution
            == "From Claude’s last answer in the session at 8:47 AM on 22 October 2026. The answer that shows this version wasn’t found.")
        #expect(made.text.origin.contains("\nCapsid couldn’t find the answer that showed this version, so the words kept with it are Claude’s last in the session, from 8:47 AM on 22 October 2026. You asked: “A question”\n"))
    }

    @Test func noAnswerIsSaidToo() {
        let made = readme(answer: nil, row: nil, question: nil)
        #expect(made.text.claudeSaid == "" && made.text.attribution == "")
        #expect(made.text.origin.contains("\nCapsid couldn’t find the answer that showed this version.\nVersion 3 of "))
    }
}

struct ShelfPeekTests {
    @Test func textFilesAreDrawnFromTheirTextAndTheRestFromQuickLook() {
        for name in ["a.md", "A.MD", "a.markdown", "a.txt", "a.csv", "a.tsv", "a.json", "a.py", "a.yaml", "a.log"] {
            #expect(ShelfPeek.wants(fileName: name), "\(name)")
        }
        for name in ["a.png", "a.xlsx", "a.pdf", "a.docx", "a.html", "a.ipynb", "README", "a.svg", "a.parquet"] {
            #expect(!ShelfPeek.wants(fileName: name), "\(name)")
        }
    }

    @Test func aNoteIsItsHeadingAndItsParagraphs() {
        let text = """
        # Plate reader QC, 21 October

        Eleven plates pass with Z′ between 0.62 and 0.78.
        Plate 7 fails because of an edge effect in column 12.

        Repeat plate 7 with a fresh seal.
        """
        #expect(ShelfPeek.make(text: text, fileName: "qc_notes.md") == .document(
            title: "Plate reader QC, 21 October",
            paragraphs: ["Eleven plates pass with Z′ between 0.62 and 0.78. Plate 7 fails because of an edge effect in column 12.",
                         "Repeat plate 7 with a fresh seal."]))
    }

    @Test func markdownsMarksAreLeftOut() {
        let text = "## **Methods** and [links](https://example.org)\n\n- one with `code`\n- two *with* emphasis\n\n> a quote\n\n1. first\n"
        #expect(ShelfPeek.make(text: text, fileName: "m.md") == .document(
            title: "Methods and links", paragraphs: ["one with code two with emphasis", "a quote", "first"]))
        #expect(ShelfPeek.plain("### A __bold__ word") == "A bold word")
        #expect(ShelfPeek.plain("plain words") == "plain words")
    }

    @Test func aHeadingThatDoesntOpenTheFileIsALineOfItsOwn() {
        #expect(ShelfPeek.make(text: "Some words first.\n\n## Then a heading\n\nAnd more.", fileName: "a.md")
            == .document(title: nil, paragraphs: ["Some words first.", "Then a heading", "And more."]))
        // A plain text file with a "#" is no different.
        #expect(ShelfPeek.make(text: "\n\n# Title\nbody", fileName: "a.txt") == .document(title: "Title", paragraphs: ["body"]))
    }

    @Test func nothingToShowIsNothing() {
        #expect(ShelfPeek.make(text: "", fileName: "a.md") == nil)
        #expect(ShelfPeek.make(text: " \n\t\n", fileName: "a.md") == nil)
        #expect(ShelfPeek.make(text: "", fileName: "a.csv") == nil)
        #expect(ShelfPeek.make(text: "words", fileName: "a.png") == nil)
        #expect(ShelfPeek.make(text: "words", fileName: "a.xlsx") == nil)
    }

    @Test func aTableIsItsFirstRowsAndColumns() {
        let csv = "plate,z_prime\r\n1,0.78\r\n2,0.80\r\n\r\n3,0.82\r\n4,0.84\r\n5,0.76\r\n6,0.78\r\n7,0.70\r\n8,0.71\r\n"
        guard case .table(let rows)? = ShelfPeek.make(text: csv, fileName: "z.csv") else { Issue.record("not a table"); return }
        #expect(rows.count == ShelfPeek.rows)
        #expect(rows.first == ["plate", "z_prime"])
        #expect(rows[1] == ["1", "0.78"] && rows[3] == ["3", "0.82"])
        let wide = "a,b,c,d,e,f\n1,2,3,4,5,6\n"
        #expect(ShelfPeek.make(text: wide, fileName: "w.csv") == .table(rows: [["a", "b", "c", "d"], ["1", "2", "3", "4"]]))
        #expect(ShelfPeek.make(text: "a\tb\n1\t2\n", fileName: "t.tsv") == .table(rows: [["a", "b"], ["1", "2"]]))
        // Rows that don't have the same number of cells stay as they are.
        #expect(ShelfPeek.make(text: "a,b\n1\n", fileName: "r.csv") == .table(rows: [["a", "b"], ["1"]]))
    }

    @Test func aQuotedCellIsOneCell() {
        #expect(ShelfPeek.split("\"Smith, J\",\"say \"\"hi\"\"\",3", by: ",") == ["Smith, J", "say \"hi\"", "3"])
        #expect(ShelfPeek.split("a,,c", by: ",") == ["a", "", "c"])
        #expect(ShelfPeek.split("", by: ",") == [""])
        #expect(ShelfPeek.split("a, b ,c", by: ",") == ["a", "b", "c"])
        #expect(ShelfPeek.split("\"open,cell", by: ",") == ["open,cell"])
    }

    @Test func codeIsItsFirstLinesAsTheyAre() {
        let json = (1...30).map { "  \"key\($0)\": \($0)," }.joined(separator: "\n")
        guard case .lines(let lines)? = ShelfPeek.make(text: "{\n\n" + json + "\n}", fileName: "a.json") else { Issue.record("not lines"); return }
        #expect(lines.count == ShelfPeek.codeLines)
        #expect(lines.first == "{" && lines[1] == "  \"key1\": 1,")
        let long = String(repeating: "x", count: 200)
        #expect(ShelfPeek.make(text: long, fileName: "a.py") == .lines([String(repeating: "x", count: 60)]))
    }
}
