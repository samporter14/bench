// KeptReadmeTests.swift — the README a kept folder carries, on made-up
// figures: what the renderer writes (the contract's own example, to the byte),
// that what it writes is read back as it was (render, parse, render: the same
// bytes, with names in every script, quotes, backslashes and line breaks), that
// the parser refuses anything the renderer didn't write, and that replacing
// the legend changes the legend and nothing else. Nothing here touches the disk.
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

<!-- Write the legend here, or in Capsid’s Kept window. -->

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

Capsid changes only the “Your legend” section of this file, and only when you edit it in the Kept window.

"""

// MARK: What the renderer writes

struct KeptReadmeTests {
    @Test func theRendererWritesTheContractsReadmeToTheByte() {
        #expect(render(record(), text()) == contractReadme)
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
        #expect(whole.contains("\n---\n\nCapsid changes only"))
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
        #expect(KeptReadme.parse(good.replacingOccurrences(of: "\n---\n\nCapsid changes", with: "\n\nCapsid changes")) == nil)
        #expect(KeptReadme.parse(String(good[..<good.range(of: "---\n\nCapsid changes")!.lowerBound])) == nil)
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
