// KeptReadmeTests.swift — the README a kept folder carries, on made-up
// figures: what the renderer writes (the contract's own example, to the byte),
// that what it writes is read back as it was (render, parse, render: the same
// bytes, with names in every script, quotes, backslashes and line breaks), that
// the parser refuses anything the renderer didn't write, and that replacing
// the legend changes the legend and nothing else, and that updating what Try
// Again changes (the file rows, "Not copied", "Checksums") changes nothing else
// either, and that what a person or their editor does to the file (words under
// the title, a blank line, no final newline, Windows line ends, the older fine
// print) neither hides the folder nor is lost by either write. Nothing here
// touches the disk.
import Foundation
import Testing
@testable import Bench

// MARK: Made-up keeps

/// 22 October 2026, 9:12 in the zone four hours behind UTC.
private let keptAt = Date(timeIntervalSince1970: 1_792_674_720)
/// The same morning, 8:12: when Claude answered.
private let answeredAt = Date(timeIntervalSince1970: 1_792_671_120)
private let zone = TimeZone(secondsFromGMT: -4 * 3600)!
private let english = Locale(identifier: "en_US")

private func record(name: String = "Fig 2B · Z′ by plate", sessionTitle: String = "Plate reader QC",
                    projectName: String = "Assay development", missing: Bool = true) -> KeptRecord {
    KeptRecord(
        name: name, keptAt: keptAt, projectID: "proj_1", projectName: projectName,
        sessionID: "frame_1", sessionTitle: sessionTitle,
        figure: KeptFile(path: "z_prime.png", role: .figure, artifact: "art_1", version: "ver_3", index: 3, of: 4,
                         sha256: "aaaa", bytes: 86_016),
        files: [
            KeptFile(path: "data/z_prime_by_plate.csv", role: .data, artifact: "art_2", version: "ver_9", sha256: "bbbb", bytes: 4_096),
            KeptFile(path: "code/plot_z_prime.py", role: .code, artifact: "art_3", version: "ver_7", sha256: "cccc", bytes: 2_048),
        ],
        missing: missing ? [KeptMissing(role: .input, name: "plate_reader.xlsx", reason: "too big to keep here (over 8 MB)")] : [],
        claudeScience: "0.1.70", capsid: "1.0")
}

/// A figure put on the shelf: no data, no code, and where it came from.
private func shelved(row: Int? = 19, question: String? = "Plot Z′ by plate, and show me where plate 7 goes wrong.",
                     answerAt: Date? = answeredAt) -> KeptRecord {
    var shelved = record(missing: false)
    shelved.files = []
    shelved.sourceRow = row
    shelved.question = question
    shelved.answerAt = answerAt
    return shelved
}

private func text(legend: String = "") -> KeptText {
    KeptText(legend: legend,
             claudeSaid: "The Z′ by plate is above 0.5 for all four plates.\n\nPlate 3 is the weakest.",
             attribution: KeptReadme.attribution(answerAt: answeredAt, timeZone: zone, locale: english),
             origin: "")
}

private func render(_ record: KeptRecord, _ text: KeptText) -> String {
    KeptReadme.render(record, text: text, timeZone: zone, locale: english)
}

/// The contract's README, word for word.
private let contractReadme = """
---
capsid_kept: 1
name: "Fig 2B · Z′ by plate"
kept_at: 2026-10-22T09:12:00-04:00
project: { id: "proj_1", name: "Assay development" }
session: { id: "frame_1", title: "Plate reader QC" }
figure: { file: "z_prime.png", artifact: "art_1", version: "ver_3", index: 3, of: 4, sha256: "aaaa", bytes: 86016 }
files:
  - { path: "data/z_prime_by_plate.csv", role: data, artifact: "art_2", version: "ver_9", sha256: "bbbb", bytes: 4096 }
  - { path: "code/plot_z_prime.py", role: code, artifact: "art_3", version: "ver_7", sha256: "cccc", bytes: 2048 }
missing:
  - { role: input, name: "plate_reader.xlsx", reason: "too big to keep here (over 8 MB)" }
claude_science: "0.1.70"
capsid: "1.0"
---

# Fig 2B · Z′ by plate

## Your legend

<!-- Write the legend here, or in Capsid’s Shelf window. -->

## What Claude said

> The Z′ by plate is above 0.5 for all four plates.
>
> Plate 3 is the weakest.

From Claude’s answer at 8:12 AM on 22 October 2026.

## Where it came from

[Plate reader QC](bench://session?project=proj_1&frame=frame_1), in Assay development.
Version 3 of 4 of z_prime.png, kept on 22 October 2026 at 9:12 AM by Capsid 1.0, from Claude Science 0.1.70. The link opens the session in Capsid on a Mac that has it.

## Not copied

- The raw input, plate_reader.xlsx: too big to keep here (over 8 MB).

---

Capsid updates the file lists, “Not copied”, “Checksums” and “Your legend” here; everything else in this file is yours.

"""

// MARK: What the renderer writes

struct KeptReadmeTests {
    @Test func theRendererWritesTheContractsReadmeToTheByte() {
        #expect(render(record(), text()) == contractReadme)
    }

    @Test func theFinePrintSaysWhatCapsidUpdatesAndThatTheRestIsTheirs() {
        #expect(KeptReadme.finePrint
            == "Capsid updates the file lists, “Not copied”, “Checksums” and “Your legend” here; everything else in this file is yours.")
        // Every README ends with it, after the divider, and with nothing else on the line.
        #expect(render(record(), text()).hasSuffix("\n---\n\n\(KeptReadme.finePrint)\n"))
        #expect(render(shelved(), text(legend: "Plate 3 was re-run.")).hasSuffix("\n---\n\n\(KeptReadme.finePrint)\n"))
        // It no longer says the legend is all Capsid changes, nor that it only changes when you edit it in the Shelf.
        #expect(!render(record(), text()).contains("changes only"))
    }

    @Test func theCommentIsThereOnlyWhileTheLegendIsEmpty() {
        let empty = render(record(), text(legend: ""))
        #expect(empty.contains(KeptReadme.legendComment))
        let written = render(record(), text(legend: "Plate 3 was re-run."))
        #expect(!written.contains(KeptReadme.legendComment))
        #expect(written.contains("## Your legend\n\nPlate 3 was re-run.\n\n## What Claude said"))
        // A legend of blanks is no legend.
        #expect(render(record(), text(legend: " \n\t\n")) == empty)
    }

    @Test func notCopiedIsThereOnlyWhenSomethingIsMissing() {
        #expect(render(record(), text()).contains("## Not copied"))
        let whole = render(record(missing: false), text())
        #expect(!whole.contains("## Not copied"))
        #expect(whole.contains("\nmissing: []\n"))
        #expect(whole.contains("\n---\n\nCapsid updates the file lists"))
    }

    @Test func emptyListsAndNilKeysAreWrittenTheSameWayEveryTime() {
        var bare = record(missing: false)
        bare.files = []
        bare.figure = KeptFile(path: "z_prime.png", role: .figure, bytes: 10)
        let markdown = render(bare, text())
        #expect(markdown.contains("\nfiles: []\nmissing: []\n"))
        #expect(markdown.contains("\nfigure: { file: \"z_prime.png\", bytes: 10 }\n"))
        #expect(!markdown.contains("null"))
        // With no version number to give, the line says only which file.
        #expect(markdown.contains("\nz_prime.png, kept on 22 October 2026 at 9:12 AM by Capsid 1.0, from Claude Science 0.1.70."))
    }

    @Test func aFigureWithNoAnswerFoundStillMakesAReadme() {
        let none = KeptText(legend: "", claudeSaid: "", attribution: "", origin: "")
        let markdown = render(record(), none)
        #expect(markdown.contains("## What Claude said\n\n## Where it came from"))
        let parsed = KeptReadme.parse(markdown)
        #expect(parsed?.text.claudeSaid == "")
        #expect(parsed?.text.attribution == "")
    }

    @Test func theTimeIsWrittenTheWayTheMacWritesIt() {
        #expect(KeptReadme.shortTime(keptAt, timeZone: zone, locale: Locale(identifier: "en_US")) == "9:12 AM")
        #expect(KeptReadme.shortTime(keptAt, timeZone: zone, locale: Locale(identifier: "en_GB")) == "09:12")
        #expect(KeptReadme.englishDate(keptAt, timeZone: zone) == "22 October 2026")
        // Past midnight in another zone it is the next day there.
        #expect(KeptReadme.englishDate(keptAt, timeZone: TimeZone(secondsFromGMT: 14 * 3600)!) == "23 October 2026")
        #expect(KeptReadme.attribution(answerAt: nil) == "From Claude’s answer.")
    }

    @Test func datesAreWrittenWithTheZonesOffset() {
        #expect(KeptReadme.rfc3339(keptAt, timeZone: zone) == "2026-10-22T09:12:00-04:00")
        #expect(KeptReadme.rfc3339(keptAt, timeZone: TimeZone(secondsFromGMT: 5 * 3600 + 1800)!) == "2026-10-22T18:42:00+05:30")
        #expect(KeptReadme.rfc3339(keptAt, timeZone: TimeZone(secondsFromGMT: 0)!) == "2026-10-22T13:12:00+00:00")
        // A fraction of a second is not written.
        #expect(KeptReadme.rfc3339(keptAt.addingTimeInterval(0.75), timeZone: zone) == "2026-10-22T09:12:00-04:00")
    }

    @Test func linesWithABreakInThemStillFitOnOneLine() throws {
        let odd = record(name: "Two\nlines\tand a \u{7} bell \u{2028}", sessionTitle: "A [bracketed] \\ title\r\nhere",
                         projectName: "Line one\nline two")
        let markdown = render(odd, text())
        let front = KeptReadme.lines(markdown).prefix { $0 != "" }
        #expect(front.contains("name: \"Two\\nlines\\tand a \\u0007 bell \\u2028\""))
        // The title line and the link text stay on their line.
        #expect(markdown.contains("\n# Two lines\tand a \u{7} bell \u{2028}\n"))
        #expect(markdown.contains("[A \\[bracketed\\] \\\\ title  here](bench://session?project=proj_1&frame=frame_1), in Line one line two."))
        let back = try #require(KeptReadme.parse(markdown))
        #expect(back.record.name == odd.name)
        #expect(back.record.sessionTitle == odd.sessionTitle)
        #expect(back.record.projectName == odd.projectName)
    }
}

// MARK: Reading it back

struct KeptReadmeRoundTripTests {
    private struct Case {
        let label: String
        let record: KeptRecord
        let text: KeptText
    }

    private static func cases() -> [Case] {
        var odd = record(name: "He said \"Z′\" \\ and left · \"Plate 3\" ✓ 日本語 Ünïcode 🧪")
        odd.sessionTitle = "Q: \"is it ok?\" \\o/"
        odd.projectName = "Ünïcode project · 日本語"
        odd.claudeScience = "0.1.70 \"beta\""
        odd.files[0].path = "data/Z′ by plate · v2.csv"
        odd.missing = [
            KeptMissing(role: .input, name: "plate_reader.xlsx", reason: "too big to keep here (over 8 MB)"),
            KeptMissing(role: .data, name: "Z′ \"raw\".csv", reason: "it wouldn't download: \\timeout\\"),
            KeptMissing(role: .code, name: "run.py", reason: "日本語 の理由"),
        ]
        var bare = record(missing: false)
        bare.files = []
        bare.figure = KeptFile(path: "z_prime.png", role: .figure, bytes: 0)
        var otherVersion = record()
        otherVersion.answerShowsVersion = 4
        var unmatched = record()
        unmatched.figure.expectedSha256 = "3f2a9c41d2e0"
        unmatched.files[0].expectedSha256 = "ffff"
        let said = KeptText(legend: "Plate 3 \"re-run\" with the \\ new lot.\n\nSecond paragraph · Z′ > 0.5.",
                            claudeSaid: "He wrote \"Z′ > 0.5\" and a path C:\\plates\n> a quote inside the quote\n\n  indented\n日本語 🧪",
                            attribution: KeptReadme.attribution(answerAt: answeredAt, timeZone: zone, locale: english),
                            origin: "")
        return [
            Case(label: "the contract's own", record: record(), text: text()),
            Case(label: "a filled legend", record: record(), text: text(legend: "Z′ is above 0.5 for every plate.")),
            Case(label: "an empty legend", record: record(), text: text(legend: "")),
            Case(label: "nothing missing, nothing else kept", record: bare, text: text()),
            Case(label: "quotes, backslashes, a middle dot and every script", record: odd, text: said),
            Case(label: "no answer found", record: record(), text: KeptText(legend: "", claudeSaid: "", attribution: "", origin: "")),
            Case(label: "an answer that shows another version", record: otherVersion, text: text()),
            Case(label: "files that don't match their checksums", record: unmatched, text: text()),
            Case(label: "a file that doesn't match, nothing missing", record: { var r = unmatched; r.missing = []; return r }(), text: text()),
            Case(label: "shelved: its row, what was asked and when the answer came", record: shelved(), text: text()),
            Case(label: "shelved: a row only", record: shelved(question: nil, answerAt: nil), text: text()),
            Case(label: "shelved: a question with quotes, a line break and every script",
                 record: shelved(row: 0, question: "Plot “Z′” by plate \\ \"all\"\n日本語 العربية Ελληνικά\ttab"), text: text()),
            Case(label: "shelved, with an answer that shows another version", record: { var r = shelved(); r.answerShowsVersion = 2; return r }(),
                 text: text()),
        ]
    }

    @Test func renderParseRenderIsTheSameBytes() throws {
        for item in Self.cases() {
            let first = render(item.record, item.text)
            let parsed = try #require(KeptReadme.parse(first), "\(item.label)")
            let second = render(parsed.record, parsed.text)
            #expect(first == second, "\(item.label)")
            #expect(Array(first.utf8) == Array(second.utf8), "\(item.label)")
            // And what came back is what went in, down to the figure's own fields.
            #expect(parsed.record == item.record, "\(item.label)")
            #expect(parsed.text.legend == item.text.legend, "\(item.label)")
            #expect(parsed.text.claudeSaid == item.text.claudeSaid, "\(item.label)")
            #expect(parsed.text.attribution == item.text.attribution, "\(item.label)")
        }
    }

    @Test func theUsualOriginIsWhatIsReadBackAndWhatIsWrittenAgain() throws {
        let markdown = render(record(), text())
        let parsed = try #require(KeptReadme.parse(markdown))
        #expect(parsed.text.origin == KeptReadme.origin(for: record(), timeZone: zone, locale: english))
        #expect(parsed.text.origin.hasPrefix("[Plate reader QC](bench://session?project=proj_1&frame=frame_1)"))
        // An origin given by the caller is written as given.
        var custom = text()
        custom.origin = "Made by hand."
        #expect(render(record(), custom).contains("## Where it came from\n\nMade by hand.\n\n## Not copied"))
    }

    @Test func aLegendCantEndEarlyOrHideTheFolder() throws {
        let tricky = "Notes\n## Not a section\n\\## already escaped\n\\\\## twice\n### a smaller heading\n---\ntext"
        let markdown = render(record(), text(legend: tricky))
        let parsed = try #require(KeptReadme.parse(markdown))
        #expect(parsed.text.legend == tricky)
        #expect(parsed.text.claudeSaid == text().claudeSaid)
        #expect(render(parsed.record, parsed.text) == markdown)
        // The same legend put in afterwards.
        let swapped = try #require(KeptReadme.replacingLegend(in: render(record(), text()), with: tricky))
        #expect(swapped == markdown)
    }

    @Test func lineEndsInTheLegendComeBackAsWritten() throws {
        let crlf = "first\r\nsecond\r\n\r\nthird"
        let parsed = try #require(KeptReadme.parse(render(record(), text(legend: crlf))))
        #expect(parsed.text.legend == crlf)
    }

    @Test func aPersonsOwnHeadingBetweenTheSectionsDoesNotHideTheFolder() throws {
        let markdown = render(record(), text())
        let edited = markdown.replacingOccurrences(of: "## Where it came from", with: "## My notes\n\nRe-ran on 3 plates.\n\n## Where it came from")
        let parsed = try #require(KeptReadme.parse(edited))
        #expect(parsed.record == record())
        #expect(parsed.text.legend == "")
        // Nor does an editor's byte order mark.
        #expect(KeptReadme.parse("\u{FEFF}" + markdown) != nil)
    }
}

// MARK: What it refuses

struct KeptReadmeRefusalTests {
    private let good = render(record(), text(legend: "Plate 3 was re-run."))

    private func without(_ line: String) -> String {
        good.replacingOccurrences(of: line + "\n", with: "")
    }

    @Test func theGoodOneIsReadAndEverySingleChangeBelowIsRefused() {
        #expect(KeptReadme.parse(good) != nil)
    }

    @Test func aFileWithoutTheMarkerIsRefused() {
        #expect(KeptReadme.parse(without("capsid_kept: 1")) == nil)
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "capsid_kept: 1", with: "capsid_kept: 2")) == nil)
        #expect(KeptReadme.parse("# Just a README\n\nNothing kept here.\n") == nil)
        #expect(KeptReadme.parse("") == nil)
    }

    @Test func frontMatterOutOfOrderIsRefused() {
        let swapped = good.replacingOccurrences(
            of: "name: \"Fig 2B · Z′ by plate\"\nkept_at: 2026-10-22T09:12:00-04:00\n",
            with: "kept_at: 2026-10-22T09:12:00-04:00\nname: \"Fig 2B · Z′ by plate\"\n")
        #expect(swapped != good)
        #expect(KeptReadme.parse(swapped) == nil)
        let figureFirst = good.replacingOccurrences(of: "figure: { file: \"z_prime.png\", artifact: \"art_1\"",
                                                    with: "figure: { artifact: \"art_1\", file: \"z_prime.png\"")
        #expect(KeptReadme.parse(figureFirst) == nil)
    }

    @Test func aMissingHeadingOrFooterIsRefused() {
        for heading in [KeptReadme.legendHeading, KeptReadme.saidHeading, KeptReadme.originHeading] {
            #expect(KeptReadme.parse(without(heading)) == nil, "\(heading)")
        }
        // Sections out of their order.
        let order = good.replacingOccurrences(of: "## What Claude said", with: "## Where it came from #")
            .replacingOccurrences(of: "## Where it came from\n", with: "## What Claude said\n")
        #expect(KeptReadme.parse(order) == nil)
        // The divider and the fine print.
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "\n---\n\nCapsid updates", with: "\n\nCapsid updates")) == nil)
        #expect(KeptReadme.parse(String(good[..<good.range(of: "---\n\nCapsid updates")!.lowerBound])) == nil)
        // The title line.
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "# Fig 2B · Z′ by plate\n\n", with: "")) == nil)
    }

    @Test func aMalformedRowIsRefused() {
        let row = "  - { path: \"data/z_prime_by_plate.csv\", role: data, artifact: \"art_2\", version: \"ver_9\", sha256: \"bbbb\", bytes: 4096 }"
        #expect(good.contains(row))
        let broken = [
            row.replacingOccurrences(of: ", bytes: 4096", with: ""),
            row.replacingOccurrences(of: "bytes: 4096", with: "bytes: lots"),
            row.replacingOccurrences(of: "role: data", with: "role: movie"),
            row.replacingOccurrences(of: "role: data", with: "role: \"data\""),
            row.replacingOccurrences(of: "path: \"data/z_prime_by_plate.csv\"", with: "path: data/z_prime_by_plate.csv"),
            row.replacingOccurrences(of: ", role: data", with: "").replacingOccurrences(of: "path: ", with: "path: \"x\", extra: 1, nothing: "),
            row.replacingOccurrences(of: " }", with: ""),
            row.replacingOccurrences(of: "\"bbbb\"", with: "\"bb\\qb\""),
            row.replacingOccurrences(of: "bytes: 4096", with: "bytes: -4096"),
            row.replacingOccurrences(of: "{ path", with: "{path"),
        ]
        for bad in broken {
            #expect(KeptReadme.parse(good.replacingOccurrences(of: row, with: bad)) == nil, "\(bad)")
        }
        // The list itself: a header with no rows, a row that isn't a map.
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "files:\n" + row + "\n  - { path: \"code/plot_z_prime.py\"", with: "files:\n  - { path: \"code/plot_z_prime.py\"")) != nil)
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "missing:\n  - { role: input, name: \"plate_reader.xlsx\", reason: \"too big to keep here (over 8 MB)\" }", with: "missing:")) == nil)
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "  - { role: input", with: "  - role: input")) == nil)
        // The strings and the date.
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "capsid: \"1.0\"", with: "capsid: 1.0")) == nil)
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "2026-10-22T09:12:00-04:00", with: "2026-02-30T09:12:00-04:00")) == nil)
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "2026-10-22T09:12:00-04:00", with: "yesterday")) == nil)
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "2026-10-22T09:12:00-04:00", with: "2026-10-22T09:12:00")) == nil)
    }

    @Test func theAnswersOtherVersionIsOneNumberRightAfterTheFigure() throws {
        var other = record()
        other.answerShowsVersion = 4
        let markdown = render(other, text())
        #expect(markdown.contains("bytes: 86016 }\nanswer_shows_version: 4\nfiles:\n"))
        #expect(try #require(KeptReadme.parse(markdown)).record.answerShowsVersion == 4)
        // Without it, the line isn't there and nothing else moves.
        #expect(!good.contains("answer_shows_version"))
        #expect(KeptReadme.parse(good)?.record.answerShowsVersion == nil)
        let line = "answer_shows_version: 4\n"
        for bad in ["answer_shows_version: four\n", "answer_shows_version: \"4\"\n", "answer_shows_version: -4\n",
                    "answer_shows_version: \n", "answer_shows_version: 4 \n"] {
            #expect(KeptReadme.parse(markdown.replacingOccurrences(of: line, with: bad)) == nil, "\(bad)")
        }
        // Anywhere but after the figure is out of order.
        let moved = markdown.replacingOccurrences(of: line, with: "")
            .replacingOccurrences(of: "claude_science: ", with: line + "claude_science: ")
        #expect(KeptReadme.parse(moved) == nil)
    }

    @Test func aChecksumThatDidntMatchIsBothChecksumsAndOneSentence() throws {
        var unmatched = record()
        unmatched.figure.expectedSha256 = "3f2a9c41d2e0"
        let markdown = render(unmatched, text())
        #expect(markdown.contains("\nfigure: { file: \"z_prime.png\", artifact: \"art_1\", version: \"ver_3\", index: 3, of: 4, sha256: \"aaaa\", expected_sha256: \"3f2a9c41d2e0\", bytes: 86016 }\n"))
        #expect(markdown.contains("## Not copied\n\n- The raw input, plate_reader.xlsx: too big to keep here (over 8 MB).\n\n## Checksums\n\n"
            + "- z_prime.png doesn’t match Claude Science’s checksum for this version (expected 3f2a9c41…, got aaaa). "
            + "It may be a reference file that changed since; check it before you use it.\n\n---\n"))
        #expect(try #require(KeptReadme.parse(markdown)).record.figure.expectedSha256 == "3f2a9c41d2e0")
        // Without one, nothing is written for it.
        #expect(!good.contains("expected_sha256") && !good.contains(KeptReadme.checksumHeading))
        // Refused: after `bytes`, before `sha256`, not quoted; the section before "Not copied".
        let field = "sha256: \"aaaa\", expected_sha256: \"3f2a9c41d2e0\", bytes: 86016"
        for bad in ["sha256: \"aaaa\", bytes: 86016, expected_sha256: \"3f2a9c41d2e0\"",
                    "expected_sha256: \"3f2a9c41d2e0\", sha256: \"aaaa\", bytes: 86016",
                    "sha256: \"aaaa\", expected_sha256: 3f2a9c41d2e0, bytes: 86016"] {
            #expect(KeptReadme.parse(markdown.replacingOccurrences(of: field, with: bad)) == nil, "\(bad)")
        }
        let swapped = markdown.replacingOccurrences(of: KeptReadme.missingHeading, with: "## placeholder")
            .replacingOccurrences(of: KeptReadme.checksumHeading, with: KeptReadme.missingHeading)
            .replacingOccurrences(of: "## placeholder", with: KeptReadme.checksumHeading)
        #expect(KeptReadme.parse(swapped) == nil)
    }

    @Test func theShelfsThreeLinesComeRightAfterTheFigureInOrderAndOnlyWhenKnown() throws {
        let markdown = render(shelved(), text())
        #expect(markdown.contains("bytes: 86016 }\nsource_row: 19\nquestion: \"Plot Z′ by plate, and show me where plate 7 goes wrong.\"\n"
            + "answer_at: 2026-10-22T08:12:00-04:00\nfiles: []\n"))
        let parsed = try #require(KeptReadme.parse(markdown)).record
        #expect(parsed.sourceRow == 19)
        #expect(parsed.question == "Plot Z′ by plate, and show me where plate 7 goes wrong.")
        #expect(parsed.answerAt == answeredAt)
        // Each is written only when it is known; a keep without them is as it was.
        #expect(!good.contains("source_row") && !good.contains("\nquestion:") && !good.contains("answer_at"))
        let rowOnly = render(shelved(question: nil, answerAt: nil), text())
        #expect(rowOnly.contains("bytes: 86016 }\nsource_row: 19\nfiles: []\n"))
        #expect(!rowOnly.contains("question:") && !rowOnly.contains("answer_at"))
        let parsedRow = try #require(KeptReadme.parse(rowOnly)).record
        #expect(parsedRow.sourceRow == 19 && parsedRow.question == nil && parsedRow.answerAt == nil)
        // Row 0 is a row.
        #expect(try #require(KeptReadme.parse(render(shelved(row: 0), text()))).record.sourceRow == 0)
        // The answer's other version goes first.
        var both = shelved()
        both.answerShowsVersion = 2
        #expect(render(both, text()).contains("bytes: 86016 }\nanswer_shows_version: 2\nsource_row: 19\n"))
    }

    @Test func theShelfsLinesAreStrictToo() {
        let markdown = render(shelved(), text())
        let row = "source_row: 19\n", question = "question: \"Plot Z′ by plate, and show me where plate 7 goes wrong.\"\n"
        let at = "answer_at: 2026-10-22T08:12:00-04:00\n"
        #expect(KeptReadme.parse(markdown) != nil)
        // The row: not a number, signed, empty, padded, quoted.
        for bad in ["source_row: nineteen\n", "source_row: -19\n", "source_row: \n", "source_row: 19 \n", "source_row: \"19\"\n"] {
            #expect(KeptReadme.parse(markdown.replacingOccurrences(of: row, with: bad)) == nil, "\(bad)")
        }
        // The question: not quoted, an escape the renderer never writes, a quote left open, text after the quote.
        for bad in ["question: Plot Z′ by plate\n", "question: \"Plot \\q\"\n", "question: \"Plot Z′\n", "question: \"Plot\" and more\n"] {
            #expect(KeptReadme.parse(markdown.replacingOccurrences(of: question, with: bad)) == nil, "\(bad)")
        }
        // The time: not a real date, no offset.
        for bad in ["answer_at: yesterday\n", "answer_at: 2026-02-30T08:12:00-04:00\n", "answer_at: 2026-10-22T08:12:00\n"] {
            #expect(KeptReadme.parse(markdown.replacingOccurrences(of: at, with: bad)) == nil, "\(bad)")
        }
        // Out of order: the time before the question, the row after the question, any of them after `files:`.
        #expect(KeptReadme.parse(markdown.replacingOccurrences(of: question + at, with: at + question)) == nil)
        #expect(KeptReadme.parse(markdown.replacingOccurrences(of: row + question, with: question + row)) == nil)
        #expect(KeptReadme.parse(markdown.replacingOccurrences(of: row, with: "").replacingOccurrences(of: "files: []\n", with: "files: []\n" + row)) == nil)
        // Twice.
        #expect(KeptReadme.parse(markdown.replacingOccurrences(of: row, with: row + row)) == nil)
    }

    @Test func theLegendCommentOfTheKeptWindowIsStillAnEmptyLegend() throws {
        let old = render(record(), text()).replacingOccurrences(of: KeptReadme.legendComment, with: KeptReadme.legacyLegendComment)
        #expect(old.contains("Kept window. -->"))
        let parsed = try #require(KeptReadme.parse(old))
        #expect(parsed.text.legend == "")
        // Writing a legend there and emptying it again brings the new comment.
        let written = try #require(KeptReadme.replacingLegend(in: old, with: "Plate 3 was re-run."))
        #expect(!written.contains("Kept window. -->"))
        let emptied = try #require(KeptReadme.replacingLegend(in: written, with: ""))
        #expect(emptied.contains(KeptReadme.legendComment) && !emptied.contains(KeptReadme.legacyLegendComment))
    }

    @Test func anyOffsetIsRead() throws {
        let same = good.replacingOccurrences(of: "2026-10-22T09:12:00-04:00", with: "2026-10-22T13:12:00Z")
        #expect(try #require(KeptReadme.parse(same)).record.keptAt == keptAt)
        let other = good.replacingOccurrences(of: "2026-10-22T09:12:00-04:00", with: "2026-10-22T18:42:00+05:30")
        #expect(try #require(KeptReadme.parse(other)).record.keptAt == keptAt)
    }
}

// MARK: Replacing the legend

struct KeptReadmeLegendTests {
    @Test func onlyTheLegendsBytesChange() throws {
        let before = render(record(), text(legend: ""))
        let after = try #require(KeptReadme.replacingLegend(in: before, with: "Plate 3 was re-run, with a new lot of reagent."))
        // Everything above the legend and everything from the next heading is the same bytes.
        let head = "## Your legend\n"
        let tail = "## What Claude said"
        func bytes(_ part: Substring) -> [UInt8] { Array(part.utf8) }
        let beforeHead = before[..<before.range(of: head)!.upperBound]
        let afterHead = after[..<after.range(of: head)!.upperBound]
        #expect(bytes(beforeHead) == bytes(afterHead))
        let beforeTail = before[before.range(of: tail)!.lowerBound...]
        let afterTail = after[after.range(of: tail)!.lowerBound...]
        #expect(bytes(beforeTail) == bytes(afterTail))
        #expect(!after.contains(KeptReadme.legendComment))
        #expect(after.contains("## Your legend\n\nPlate 3 was re-run, with a new lot of reagent.\n\n## What Claude said"))
        // It is the file the renderer would have written with that legend.
        #expect(after == render(record(), text(legend: "Plate 3 was re-run, with a new lot of reagent.")))
    }

    @Test func theCommentComesBackWhenTheLegendIsEmptiedAgain() throws {
        let empty = render(record(), text(legend: ""))
        let filled = try #require(KeptReadme.replacingLegend(in: empty, with: "Z′ above 0.5."))
        #expect(!filled.contains(KeptReadme.legendComment))
        let emptied = try #require(KeptReadme.replacingLegend(in: filled, with: ""))
        #expect(emptied == empty)
        #expect(Array(emptied.utf8) == Array(empty.utf8))
        // A legend of blanks is empty too, and doing it twice changes nothing more.
        #expect(KeptReadme.replacingLegend(in: filled, with: "  \n \n") == empty)
        #expect(KeptReadme.replacingLegend(in: filled, with: "Z′ above 0.5.") == filled)
    }

    @Test func everyOtherByteStaysEvenWhenAPersonEditedTheFile() throws {
        // A README a person has changed elsewhere: another heading of theirs, odd spacing, a final line.
        let edited = render(record(), text(legend: "old"))
            .replacingOccurrences(of: "## What Claude said", with: "## My notes\n\n  Re-ran on 3 plates.   \n\n\n## What Claude said")
            + "\nAdded by hand.\r\n"
        let after = try #require(KeptReadme.replacingLegend(in: edited, with: "new legend"))
        #expect(after == edited.replacingOccurrences(of: "\nold\n", with: "\nnew legend\n"))
    }

    @Test func aFileWithoutTheHeadingIsRefused() {
        #expect(KeptReadme.replacingLegend(in: "# Nothing\n\nText.\n", with: "x") == nil)
        #expect(KeptReadme.replacingLegend(in: "## Your legend\n\nno heading follows\n", with: "x") == nil)
    }

    @Test func legendsOfEveryScriptSurvive() throws {
        let legend = "Z′ · 日本語 · Ünïcode 🧪 \"quoted\" \\ back"
        let after = try #require(KeptReadme.replacingLegend(in: render(record(), text()), with: legend))
        let parsed = try #require(KeptReadme.parse(after))
        #expect(parsed.text.legend == legend)
        #expect(parsed.record == record())
    }
}

// MARK: Updating only what Capsid keeps in it

/// What Try Again does to a README: the file rows and the "Not copied" and
/// "Checksums" sections change, and every other byte of the file is as it was.
struct KeptReadmeUpdateTests {
    private let landed = KeptFile(path: "input/plate_reader.xlsx", role: .input, artifact: "art_4", version: "ver_1",
                                  sha256: "dddd", bytes: 9)
    /// A file whose bytes didn't match Claude Science's checksum.
    private let stale = KeptFile(path: "input/plate_layout.csv", role: .input, artifact: "art_5", version: "ver_2",
                                 sha256: "eeee", bytes: 12, expectedSha256: "ffff0000")

    private func update(_ markdown: String, to record: KeptRecord) -> String? {
        KeptReadme.updating(markdown, files: record.files, missing: record.missing)
    }

    private func rendered(_ record: KeptRecord, zone: TimeZone = zone, legend: String = "") -> String {
        KeptReadme.render(record, text: text(legend: legend), timeZone: zone, locale: english)
    }

    @Test func aReadmeNobodyTouchedComesOutAsTheRendererWouldWriteIt() throws {
        let missing = record()
        var whole = record(missing: false)
        whole.files.append(landed)
        var someMissing = record()
        someMissing.missing[0].reason = "The folder didn\u{2019}t respond."
        var checksum = record()
        checksum.files.append(stale)
        var checksumAndMissing = record()
        checksumAndMissing.files.append(stale)
        var neither = record(missing: false)
        neither.files.append(landed)
        var shelvedThenKept = shelved()
        shelvedThenKept.files = [landed]
        let cases: [(String, KeptRecord, KeptRecord)] = [
            ("everything lands", missing, whole),
            ("nothing changes", missing, missing),
            ("a reason changes", missing, someMissing),
            ("a checksum that doesn\u{2019}t match appears, a file is still missing", missing, checksum),
            ("both sections appear", record(missing: false), checksumAndMissing),
            ("both go", checksumAndMissing, neither),
            ("the checksum goes, Not copied stays", checksum, missing),
            ("a list that was empty gets a row", shelved(), shelvedThenKept),
        ]
        for (name, before, after) in cases {
            let result = try #require(update(rendered(before), to: after), "\(name)")
            #expect(result == rendered(after), "\(name)")
        }
    }

    @Test func theFrontMattersTimeIsNotWrittenAgainInTheZoneOfTheMomentTheKeepWasMadeIn() throws {
        // A README made on a Mac in India: its kept_at and the dates in it keep their zone.
        let india = TimeZone(secondsFromGMT: 5 * 3600 + 1800)!
        var whole = record(missing: false)
        whole.files.append(landed)
        let before = rendered(record(), zone: india)
        #expect(before.contains("kept_at: 2026-10-22T18:42:00+05:30"))
        let result = try #require(update(before, to: whole))
        #expect(result == rendered(whole, zone: india))
        #expect(result.contains("kept_at: 2026-10-22T18:42:00+05:30"))
    }

    @Test func aSectionAPersonAddedAndTheTextAroundItStayByteForByte() throws {
        let original = rendered(record(), legend: "Plate 3 was re-run.")
        // A section before the legend, one between Claude's words and the origin (with odd spacing and
        // a Windows editor's line ends), one after "Not copied", and a line after the fine print.
        let edited = original
            .replacingOccurrences(of: "## Your legend", with: "## Lab notes\n\nBench 4, lot 2207.\n\n## Your legend")
            .replacingOccurrences(of: "## Where it came from", with: "## Reviewer\r\n\r\n  Check plate 7.   \r\n\r\n\r\n## Where it came from")
            .replacingOccurrences(of: "---\n\nCapsid updates", with: "## Follow-ups\n\n- Re-run plate 7\n\n---\n\nCapsid updates")
            + "\nAdded by hand.\r\n"
        #expect(KeptReadme.parse(edited) != nil)

        var whole = record(missing: false)
        whole.files.append(landed)
        let result = try #require(update(edited, to: whole))

        // Exactly the edited file, with the input listed, nothing missing, and "Not copied" gone.
        let reason = "too big to keep here (over 8 MB)"
        let expected = edited
            .replacingOccurrences(of: "missing:\n  - { role: input, name: \"plate_reader.xlsx\", reason: \"\(reason)\" }\n",
                                  with: "missing: []\n")
            .replacingOccurrences(of: "  - { path: \"code/plot_z_prime.py\", role: code, artifact: \"art_3\", version: \"ver_7\", sha256: \"cccc\", bytes: 2048 }\n",
                                  with: "  - { path: \"code/plot_z_prime.py\", role: code, artifact: \"art_3\", version: \"ver_7\", sha256: \"cccc\", bytes: 2048 }\n"
                                      + "  - { path: \"input/plate_reader.xlsx\", role: input, artifact: \"art_4\", version: \"ver_1\", sha256: \"dddd\", bytes: 9 }\n")
            .replacingOccurrences(of: "## Not copied\n\n- The raw input, plate_reader.xlsx: \(reason).\n\n", with: "")
        #expect(result == expected)
        for kept in ["## Lab notes\n\nBench 4, lot 2207.\n\n", "  Check plate 7.   \r\n\r\n\r\n", "## Follow-ups\n\n- Re-run plate 7\n\n",
                     "Plate 3 was re-run.", "\nAdded by hand.\r\n"] {
            #expect(result.contains(kept), "\(kept.debugDescription)")
        }
        let back = try #require(KeptReadme.parse(result))
        #expect(back.record.files.map(\.path) == ["data/z_prime_by_plate.csv", "code/plot_z_prime.py", "input/plate_reader.xlsx"])
        #expect(back.record.missing.isEmpty)
        #expect(back.text.legend == "Plate 3 was re-run.")
    }

    @Test func aNewSectionOfCapsidsGoesBesideItsOwnAndAPersonsGoOnAfter() throws {
        let original = rendered(record(missing: false))
        let edited = original.replacingOccurrences(of: "---\n\nCapsid updates", with: "## Follow-ups\n\nRe-run plate 7.\n\n---\n\nCapsid updates")
        var after = record()
        after.files.append(stale)
        let result = try #require(update(edited, to: after))
        let order = ["## Where it came from", "## Not copied", "## Checksums", "## Follow-ups", "\n---\n\nCapsid updates"]
        let places = try order.map { try #require(result.range(of: $0)?.lowerBound) }
        #expect(places == places.sorted())
        #expect(result.contains("## Follow-ups\n\nRe-run plate 7.\n\n---\n\nCapsid updates"))
        let back = try #require(KeptReadme.parse(result))
        #expect(back.record.missing == after.missing)
        #expect(KeptReadme.mismatched(back.record).map(\.path) == ["input/plate_layout.csv"])

        // The same when a person's text ends the "Where it came from" section.
        let trailing = original.replacingOccurrences(of: "The link opens the session in Capsid on a Mac that has it.\n",
                                                     with: "The link opens the session in Capsid on a Mac that has it.\nMy own line.\n")
        let placed = try #require(update(trailing, to: after))
        #expect(placed.contains("My own line.\n\n## Not copied"))
    }

    @Test func aPersonsNoteInsideNotCopiedStaysWhenTheListGoes() throws {
        let original = rendered(record())
        let note = "Chasing this with the vendor.\n\n"
        let edited = original.replacingOccurrences(of: "over 8 MB).\n\n---", with: "over 8 MB).\n\n\(note)---")
        #expect(edited != original)
        var whole = record(missing: false)
        whole.files.append(landed)
        let result = try #require(update(edited, to: whole))
        // The heading and the note stay, and the row doesn't.
        #expect(result.contains("## Not copied\n\n\n\(note)---"))
        #expect(!result.contains("plate_reader.xlsx: too big"))
        #expect(KeptReadme.parse(result)?.record.missing.isEmpty == true)
        // With the list back in it, the note is still after it.
        let again = try #require(update(result, to: record()))
        #expect(again.contains("\n\(note)---"))
        #expect(again.contains("- The raw input, plate_reader.xlsx: too big to keep here (over 8 MB).\n"))
    }

    @Test func aSectionWhoseListAPersonDeletedGetsItBack() throws {
        let original = rendered(record())
        let emptied = original.replacingOccurrences(of: "- The raw input, plate_reader.xlsx: too big to keep here (over 8 MB).\n", with: "")
        #expect(emptied != original)
        #expect(update(emptied, to: record()) == original)
    }

    /// What every README said before Try Again also updated the file lists and two sections.
    private let oldFinePrint = "Capsid changes only the “Your legend” section of this file, and only when you edit it in the Shelf window."

    @Test func aReadmeWithTheOldFinePrintIsStillReadAndIsNotRewritten() throws {
        let old = rendered(record(), legend: "Plate 3 was re-run.").replacingOccurrences(of: KeptReadme.finePrint, with: oldFinePrint)
        #expect(old.hasSuffix("\n---\n\n\(oldFinePrint)\n"))
        let parsed = try #require(KeptReadme.parse(old))
        #expect(parsed.record == record())
        #expect(parsed.text.legend == "Plate 3 was re-run.")
        // Neither write touches the line: only a README made now says the new thing.
        let legended = try #require(KeptReadme.replacingLegend(in: old, with: "Other."))
        #expect(legended.hasSuffix("\n---\n\n\(oldFinePrint)\n"))
        var whole = record(missing: false)
        whole.files.append(landed)
        let updated = try #require(update(old, to: whole))
        #expect(updated.hasSuffix("\n---\n\n\(oldFinePrint)\n"))
        #expect(!updated.contains(KeptReadme.finePrint))
        // Nor does the parser mind words of a person's own there.
        let own = rendered(record()).replacingOccurrences(of: KeptReadme.finePrint, with: "Mine now.")
        #expect(KeptReadme.parse(own)?.record == record())
        #expect(update(own, to: whole)?.hasSuffix("\n---\n\nMine now.\n") == true)
    }

    @Test func aByteOrderMarkStays() throws {
        var whole = record(missing: false)
        whole.files.append(landed)
        let marked = "\u{FEFF}" + rendered(record())
        let result = try #require(update(marked, to: whole))
        #expect(result == "\u{FEFF}" + rendered(whole))
    }

    @Test func aFileThatIsntOneCapsidReadsIsLeftAlone() {
        #expect(update("# Not ours\n\nText.\n", to: record()) == nil)
        #expect(update("", to: record()) == nil)
        // Nor one whose front matter is out of order.
        let swapped = rendered(record()).replacingOccurrences(of: "capsid_kept: 1\nname:", with: "name:")
        #expect(update(swapped, to: record()) == nil)
    }
}

// MARK: What a person may do to the file and still have it read

/// Harmless things a person, or their editor, does to a README: words under the
/// title, an extra blank line, no final newline, Windows line ends. The folder
/// stays on the Shelf, and what Capsid writes afterwards leaves every byte of
/// what they did as it was.
struct KeptReadmeShapeTests {
    private static let words = "Draft for the plate 7 discussion.\nCheck the cutoff with Dana before it goes in."
    private let base = render(record(), text(legend: "Plate 3 was re-run."))
    private let title = "# Fig 2B · Z′ by plate\n\n"
    private let landed = KeptFile(path: "input/plate_reader.xlsx", role: .input, artifact: "art_4", version: "ver_1",
                                  sha256: "dddd", bytes: 9)

    /// `markdown` with `words` between the title and the first section.
    private func underTitle(_ words: String = Self.words, in markdown: String? = nil) -> String {
        (markdown ?? base).replacingOccurrences(of: title, with: title + words + "\n\n")
    }

    /// The same file with Windows line ends, as an editor on Windows saves it.
    private func windows(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "\n", with: "\r\n")
    }

    private func hasCarriageReturn(_ text: String) -> Bool { text.unicodeScalars.contains("\r") }

    /// Whether any line feed is not behind a carriage return.
    private func hasPlainLineFeed(_ text: String) -> Bool {
        var previous: Unicode.Scalar = " "
        for scalar in text.unicodeScalars {
            if scalar == "\n", previous != "\r" { return true }
            previous = scalar
        }
        return false
    }

    /// The whole README for the record with `landed` listed and nothing missing.
    private var landedRecord: KeptRecord {
        var whole = record(missing: false)
        whole.files.append(landed)
        return whole
    }

    // MARK: Words under the title

    @Test func wordsUnderTheTitleDoNotHideTheFolder() throws {
        let shapes: [(String, String)] = [
            ("two lines", Self.words),
            ("a list", "- Bench 4\n- Lot 2207"),
            ("a quote and a smaller heading", "> Ask Dana.\n\n### Open points\n\nPlate 7."),
            ("a horizontal rule", "Draft.\n\n---\n\nStill draft."),
            ("indented, with trailing spaces and a tab", "    Re-ran on 3 plates.   \n\tAnd one more.  "),
            ("a backslash before a heading mark", "\\## not a section"),
            ("Windows line ends inside", "First line.\r\nSecond line."),
            ("every script", "Z′ · 日本語 · Ünïcode 🧪 \"quoted\" \\ back"),
        ]
        for (label, words) in shapes {
            let parsed = try #require(KeptReadme.parse(underTitle(words)), "\(label)")
            #expect(parsed.record == record(), "\(label)")
            // The words are the person's: they are not folded into the legend or anything Capsid writes.
            #expect(parsed.text.legend == "Plate 3 was re-run.", "\(label)")
            #expect(parsed.text.claudeSaid == text().claudeSaid, "\(label)")
            #expect(parsed.text.attribution == text().attribution, "\(label)")
            #expect(parsed.text.origin == KeptReadme.origin(for: record(), timeZone: zone, locale: english), "\(label)")
        }
        // No blank line between the title and the words, and words ahead of a heading of the person's own.
        #expect(KeptReadme.parse(base.replacingOccurrences(of: title, with: "# Fig 2B · Z′ by plate\nWords right under it.\n\n")) != nil)
        #expect(KeptReadme.parse(underTitle("Words.\n\n## My notes\n\nMore words.")) != nil)
        // The front matter above them is still the record's alone: words before the title are not a shape it reads.
        #expect(KeptReadme.parse(base.replacingOccurrences(of: "---\n\n# Fig", with: "---\n\nWords first.\n\n# Fig")) == nil)
    }

    @Test func wordsUnderTheTitleStayByteForByteWhenTheLegendIsChanged() throws {
        let edited = underTitle("    Odd   spacing, a tab\there.  \n\n\nAnd a second paragraph.")
        let after = try #require(KeptReadme.replacingLegend(in: edited, with: "New legend."))
        #expect(after == edited.replacingOccurrences(of: "\nPlate 3 was re-run.\n", with: "\nNew legend.\n"))
        #expect(after.contains("# Fig 2B · Z′ by plate\n\n    Odd   spacing, a tab\there.  \n\n\nAnd a second paragraph.\n\n## Your legend"))
        #expect(KeptReadme.parse(after)?.text.legend == "New legend.")
        // And put back, it is the file it was.
        #expect(KeptReadme.replacingLegend(in: after, with: "Plate 3 was re-run.") == edited)
    }

    @Test func wordsUnderTheTitleStayByteForByteWhenTryAgainUpdatesTheReadme() throws {
        let edited = underTitle("    Odd   spacing, a tab\there.  \n\n\nAnd a second paragraph.")
        let result = try #require(KeptReadme.updating(edited, files: landedRecord.files, missing: []))
        let reason = "too big to keep here (over 8 MB)"
        let expected = edited
            .replacingOccurrences(of: "missing:\n  - { role: input, name: \"plate_reader.xlsx\", reason: \"\(reason)\" }\n", with: "missing: []\n")
            .replacingOccurrences(of: "bytes: 2048 }\n", with: "bytes: 2048 }\n  - { path: \"input/plate_reader.xlsx\", role: input, artifact: \"art_4\", version: \"ver_1\", sha256: \"dddd\", bytes: 9 }\n")
            .replacingOccurrences(of: "## Not copied\n\n- The raw input, plate_reader.xlsx: \(reason).\n\n", with: "")
        #expect(result == expected)
        #expect(result.contains("# Fig 2B · Z′ by plate\n\n    Odd   spacing, a tab\there.  \n\n\nAnd a second paragraph.\n\n## Your legend"))
        // A section that was not there is made, and the words do not move.
        var stale = record()
        stale.files.append(KeptFile(path: "input/plate_layout.csv", role: .input, artifact: "art_5", version: "ver_2",
                                    sha256: "eeee", bytes: 12, expectedSha256: "ffff0000"))
        let withChecksums = try #require(KeptReadme.updating(edited, files: stale.files, missing: stale.missing))
        #expect(withChecksums.contains("# Fig 2B · Z′ by plate\n\n    Odd   spacing, a tab\there.  \n\n\nAnd a second paragraph.\n\n## Your legend"))
        #expect(withChecksums.contains("## Checksums"))
        #expect(KeptReadme.parse(withChecksums)?.record.files == stale.files)
    }

    @Test func aFolderWithWordsUnderItsTitleSurvivesBothWritesInEitherOrder() throws {
        let edited = underTitle()
        let updated = try #require(KeptReadme.updating(edited, files: landedRecord.files, missing: []))
        let legended = try #require(KeptReadme.replacingLegend(in: updated, with: "A legend."))
        let back = try #require(KeptReadme.parse(legended))
        #expect(back.record == landedRecord)
        #expect(back.text.legend == "A legend.")
        #expect(legended.contains("# Fig 2B · Z′ by plate\n\n\(Self.words)\n\n## Your legend"))
        let other = try #require(KeptReadme.replacingLegend(in: edited, with: "A legend."))
        let otherWay = try #require(KeptReadme.updating(other, files: landedRecord.files, missing: []))
        #expect(otherWay == legended)
    }

    // MARK: The lines that say why there is no data or code

    @Test func theLinesSayingWhyNothingWasKeptStillRead() throws {
        let usual = KeptReadme.origin(for: record(missing: false), timeZone: zone, locale: english)
        let endings: [(String, [String])] = [
            ("an upload", [KeepRules.uploadSentence]),
            ("inputs still pending", [KeepRules.pendingSentence]),
            ("data and code left out", ["The data it was drawn from: not kept. No source data recorded.",
                                        "The code that drew it: not kept. Left out when it was kept."]),
        ]
        for (label, lines) in endings {
            var said = text()
            said.origin = ([usual] + lines).joined(separator: "\n")
            let first = render(record(missing: false), said)
            let parsed = try #require(KeptReadme.parse(first), "\(label)")
            #expect(parsed.text.origin == said.origin, "\(label)")
            #expect(render(parsed.record, parsed.text) == first, "\(label)")
            // Through both writes, with words under the title as well.
            let edited = underTitle(in: first)
            let legended = try #require(KeptReadme.replacingLegend(in: edited, with: "A legend."), "\(label)")
            let updated = try #require(KeptReadme.updating(legended, files: record(missing: false).files, missing: []), "\(label)")
            #expect(updated == legended, "\(label)")
            #expect(KeptReadme.parse(updated)?.text.origin == said.origin, "\(label)")
        }
    }

    // MARK: Blank lines

    @Test func anExtraBlankLineInTheTextPartsOfTheFileIsHarmless() throws {
        let doubled: [(String, String)] = [
            ("after the front matter", base.replacingOccurrences(of: "capsid: \"1.0\"\n---\n\n", with: "capsid: \"1.0\"\n---\n\n\n")),
            ("after the title", base.replacingOccurrences(of: title, with: title + "\n")),
            ("between the sections", base.replacingOccurrences(of: "\n## Where it came from", with: "\n\n## Where it came from")),
            ("before the divider", base.replacingOccurrences(of: "\n---\n\nCapsid", with: "\n\n\n---\n\nCapsid")),
            ("after the divider", base.replacingOccurrences(of: "---\n\nCapsid", with: "---\n\n\n\nCapsid")),
            ("after the fine print", base + "\n\n"),
        ]
        for (label, markdown) in doubled {
            #expect(markdown != base, "\(label)")
            let parsed = try #require(KeptReadme.parse(markdown), "\(label)")
            #expect(parsed.record == record(), "\(label)")
            #expect(parsed.text.legend == "Plate 3 was re-run.", "\(label)")
            // Both writes leave the extra line where it is.
            let legended = try #require(KeptReadme.replacingLegend(in: markdown, with: "New."), "\(label)")
            #expect(legended == markdown.replacingOccurrences(of: "\nPlate 3 was re-run.\n", with: "\nNew.\n"), "\(label)")
            let updated = try #require(KeptReadme.updating(markdown, files: record().files, missing: record().missing), "\(label)")
            #expect(updated == markdown, "\(label)")
        }
    }

    @Test func aBlankLineInsideTheLegendsOwnSectionIsTheLegendsAndIsWrittenAgainWithIt() throws {
        // Between the legend and the next heading, the lines are the legend's: saved again, they are one blank line.
        let spaced = base.replacingOccurrences(of: "\n## What Claude said", with: "\n\n\n## What Claude said")
        #expect(KeptReadme.parse(spaced)?.text.legend == "Plate 3 was re-run.")
        #expect(KeptReadme.replacingLegend(in: spaced, with: "Plate 3 was re-run.") == base)
    }

    @Test func aBlankLineInsideTheFrontMatterIsStillRefused() {
        // The front matter is the record, in the shape Capsid writes it; the parser reads that shape and no other.
        let cases = [("after the opening line", base.replacingOccurrences(of: "---\ncapsid_kept: 1", with: "---\n\ncapsid_kept: 1")),
                     ("between the rows", base.replacingOccurrences(of: "files:\n  - { path: \"data/z_prime_by_plate.csv\"",
                                                                      with: "files:\n\n  - { path: \"data/z_prime_by_plate.csv\"")),
                     ("before the closing line", base.replacingOccurrences(of: "capsid: \"1.0\"\n---", with: "capsid: \"1.0\"\n\n---"))]
        for (label, markdown) in cases {
            #expect(markdown != base, "\(label)")
            #expect(KeptReadme.parse(markdown) == nil, "\(label)")
        }
    }

    // MARK: No final newline

    @Test func aFileWithoutAFinalNewlineIsReadAndStaysWithout() throws {
        let cut = String(base.dropLast())
        #expect(cut.hasSuffix("is yours.") && base.hasSuffix("is yours.\n"))
        let parsed = try #require(KeptReadme.parse(cut))
        #expect(parsed.record == record())
        #expect(parsed.text.legend == "Plate 3 was re-run.")
        let legended = try #require(KeptReadme.replacingLegend(in: cut, with: "New."))
        #expect(legended == cut.replacingOccurrences(of: "\nPlate 3 was re-run.\n", with: "\nNew.\n"))
        #expect(!legended.hasSuffix("\n"))
        let updated = try #require(KeptReadme.updating(cut, files: landedRecord.files, missing: []))
        #expect(!updated.hasSuffix("\n") && updated.hasSuffix("is yours."))
        #expect(KeptReadme.parse(updated)?.record == landedRecord)
    }

    // MARK: Windows line ends

    @Test func aFileWithWindowsLineEndsIsReadAsTheSameReadme() throws {
        let crlf = windows(base)
        #expect(crlf.contains("---\r\ncapsid_kept: 1\r\n"))
        let parsed = try #require(KeptReadme.parse(crlf))
        #expect(parsed.record == record())
        // The words come back as they were typed, with no carriage return in them.
        #expect(parsed.text == KeptReadme.parse(base)?.text)
        #expect(!hasCarriageReturn(parsed.text.legend) && !hasCarriageReturn(parsed.text.claudeSaid)
            && !hasCarriageReturn(parsed.text.attribution) && !hasCarriageReturn(parsed.text.origin))
        // A legend over several lines, with words under the title.
        let many = windows(underTitle(in: render(record(), text(legend: "First line.\n\nSecond paragraph."))))
        #expect(KeptReadme.parse(many)?.text.legend == "First line.\n\nSecond paragraph.")
        // A byte order mark in front, and no line end at the very end.
        #expect(KeptReadme.parse("\u{FEFF}" + crlf)?.record == record())
        #expect(KeptReadme.parse(String(crlf.unicodeScalars.dropLast(2)))?.record == record())
    }

    @Test func aLegendIsReplacedInAWindowsFileAndItsLineEndsStay() throws {
        let crlf = windows(underTitle())
        let after = try #require(KeptReadme.replacingLegend(in: crlf, with: "First line.\nSecond line."))
        // Every other byte is as it was, and every line end in it is still a Windows one.
        #expect(after == crlf.replacingOccurrences(of: "\r\nPlate 3 was re-run.\r\n", with: "\r\nFirst line.\r\nSecond line.\r\n"))
        #expect(!hasPlainLineFeed(after))
        #expect(KeptReadme.parse(after)?.text.legend == "First line.\nSecond line.")
        // The comment comes back when it is emptied, in the same line ends.
        let emptied = try #require(KeptReadme.replacingLegend(in: after, with: ""))
        #expect(emptied == crlf.replacingOccurrences(of: "Plate 3 was re-run.", with: KeptReadme.legendComment))
        // A legend that came with Windows line ends of its own is not doubled.
        let pasted = try #require(KeptReadme.replacingLegend(in: crlf, with: "One.\r\nTwo."))
        #expect(pasted.contains("\r\nOne.\r\nTwo.\r\n") && !pasted.contains("\r\r"))
        // With a byte order mark in front, and with no line end at the end.
        let marked = try #require(KeptReadme.replacingLegend(in: "\u{FEFF}" + crlf, with: "New."))
        #expect(marked == "\u{FEFF}" + crlf.replacingOccurrences(of: "Plate 3 was re-run.", with: "New."))
        let cut = String(crlf.unicodeScalars.dropLast(2))
        let cutAfter = try #require(KeptReadme.replacingLegend(in: cut, with: "New."))
        #expect(cutAfter == cut.replacingOccurrences(of: "Plate 3 was re-run.", with: "New."))
    }

    @Test func tryAgainUpdatesAWindowsFileAndItsLineEndsStay() throws {
        let crlf = windows(underTitle())
        let result = try #require(KeptReadme.updating(crlf, files: landedRecord.files, missing: []))
        let unix = try #require(KeptReadme.updating(underTitle(), files: landedRecord.files, missing: []))
        #expect(result == windows(unix))
        #expect(!hasPlainLineFeed(result))
        // Sections that were not there are made, in the same line ends.
        var stale = record()
        stale.files.append(KeptFile(path: "input/plate_layout.csv", role: .input, artifact: "art_5", version: "ver_2",
                                    sha256: "eeee", bytes: 12, expectedSha256: "ffff0000"))
        let checksums = try #require(KeptReadme.updating(crlf, files: stale.files, missing: stale.missing))
        #expect(!hasPlainLineFeed(checksums))
        #expect(checksums.contains("\r\n## Checksums\r\n\r\n- input/plate_layout.csv doesn’t match"))
        #expect(KeptReadme.parse(checksums)?.record.files == stale.files)
        // With a byte order mark in front.
        let marked = try #require(KeptReadme.updating("\u{FEFF}" + crlf, files: landedRecord.files, missing: []))
        #expect(marked == "\u{FEFF}" + result)
    }

    @Test func aFileWhoseLineEndsAreMixedIsReadButNotWrittenOver() throws {
        // Windows line ends, and a line a person added in an editor that wrote a plain one.
        let mixed = windows(base) + "Added by hand.\n"
        let parsed = try #require(KeptReadme.parse(mixed))
        #expect(parsed.record == record())
        #expect(parsed.text.legend == "Plate 3 was re-run.")
        // The line ends could not be put back as they were, so neither write goes ahead.
        #expect(KeptReadme.replacingLegend(in: mixed, with: "New.") == nil)
        #expect(KeptReadme.updating(mixed, files: landedRecord.files, missing: []) == nil)
        // A file with plain line ends and Windows ones in a person's own lines is not a Windows file: those stay as written.
        let plain = base.replacingOccurrences(of: "## What Claude said", with: "## My notes\r\n\r\nWindows lines.\r\n\r\n## What Claude said")
        #expect(KeptReadme.replacingLegend(in: plain, with: "New.") == plain.replacingOccurrences(of: "\nPlate 3 was re-run.\n", with: "\nNew.\n"))
        #expect(KeptReadme.parse(plain)?.text.legend == "Plate 3 was re-run.")
    }
}
