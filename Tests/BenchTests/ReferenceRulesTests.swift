// ReferenceRulesTests.swift — the reference reader's pure rules: how rows
// become replies (a reply runs from one of the user's turns to the next, its
// figures from every step, one per artifact), the caption, the time, the
// source line and the copied text.
import AppKit
import Foundation
import Testing
@testable import Bench

struct ReferenceRulesTests {
    static let session = SessionStatus(
        id: "00000000-0000-4000-8000-000000000001", projectID: "00000000-0000-4000-8000-0000000000aa",
        projectName: "Assay development", title: "Plate reader QC", state: .finished, updatedAt: Date(), startedAt: nil)
    static let untitled = SessionStatus(
        id: "00000000-0000-4000-8000-000000000002", projectID: "00000000-0000-4000-8000-0000000000aa",
        projectName: "Assay development", title: "", state: .finished, updatedAt: Date(), startedAt: nil)
    static let london = TimeZone(identifier: "Europe/London")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar
    }
    static let locale = Locale(identifier: "en_GB")
    /// 22 October 2026, 08:47 in London.
    static let at = Date(timeIntervalSince1970: 1_792_655_220)
    static let now = at.addingTimeInterval(3_600)

    static func file(_ v: Int, artifact: Int, name: String = "plot.png", kind: ArtifactKind = .image) -> HistoryFile {
        HistoryFile(v: String(format: "aaaaaaaa-0000-4000-8000-%012d", v), a: String(format: "bbbbbbbb-0000-4000-8000-%012d", artifact),
                    name: name, kind: kind, size: nil)
    }

    @Test func aReplyRunsFromTheUsersTurnToTheNextAndGathersEveryFigure() {
        let draft = Self.file(1, artifact: 1), final = Self.file(2, artifact: 1), heatmap = Self.file(3, artifact: 2, name: "map.png")
        let table = Self.file(4, artifact: 3, name: "plates.csv", kind: .table)
        let upload = Self.file(5, artifact: 4, name: "mine.png")
        let items: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "  Plot it.  ", cut: false, files: [upload]),
            .turn(i: 1, role: .claude, at: Self.at, text: "Let me plot it.", cut: false, files: []),
            .steps(i: 2, line: "Ran code", failed: false, files: [draft]),
            .steps(i: 3, line: "Ran code", failed: false, files: [heatmap, table]),
            .steps(i: 4, line: "Ran code", failed: false, files: [final]),
            .plan(i: 5, steps: 2),
            .toYou(i: 6, text: "Halfway there.", files: []),
            .turn(i: 7, role: .claude, at: Self.at.addingTimeInterval(60), text: "Here it is.", cut: true, files: []),
            .turn(i: 8, role: .claude, at: nil, text: "   ", cut: false, files: []),
            .turn(i: 9, role: .you, at: nil, text: "Thanks.", cut: false, files: []),
        ]
        let answers = ReferenceRules.answers(items: items, reachedStart: true, whole: [:])
        #expect(answers.count == 1)
        let reply = answers[0]
        #expect(reply.id == 8)
        #expect(reply.question == "Plot it.")
        // The last version of each artifact, in the place it first appeared; no table, no upload.
        #expect(reply.figures == [final, heatmap])
        #expect(reply.parts.map(\.i) == [1, 6, 7])
        #expect(reply.text == "Let me plot it.\n\nHalfway there.\n\nHere it is.")
        #expect(reply.cutRows == [7])
        #expect(reply.at == Self.at.addingTimeInterval(60))
        #expect(reply.complete)
        // Read whole since: the text is the whole one, and nothing is cut.
        let whole = ReferenceRules.answers(items: items, reachedStart: true, whole: [7: "Here it is, in full."])[0]
        #expect(whole.text.hasSuffix("Here it is, in full."))
        #expect(whole.cutRows.isEmpty)
    }

    @Test func rowsBeforeTheFirstQuestionAreAReplyWhoseStartIsUnread() {
        let items: [HistoryItem] = [
            .steps(i: 40, line: "Ran code", failed: false, files: []),
            .turn(i: 41, role: .claude, at: nil, text: "Earlier words.", cut: false, files: []),
            .turn(i: 42, role: .you, at: nil, text: "Next?", cut: false, files: []),
            .turn(i: 43, role: .claude, at: nil, text: "Next.", cut: false, files: []),
        ]
        let partial = ReferenceRules.answers(items: items, reachedStart: false, whole: [:])
        #expect(partial.map(\.id) == [41, 43])
        #expect(partial[0].complete == false)
        #expect(partial[0].question == nil)
        #expect(partial[1].complete)
        // At the history's start, the first rows are a reply of their own.
        #expect(ReferenceRules.answers(items: items, reachedStart: true, whole: [:])[0].complete)
    }

    @Test func aStretchWithNeitherWordsNorFiguresIsNoReply() {
        let items: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "Go.", cut: false, files: []),
            .steps(i: 1, line: "Ran code", failed: false, files: []),
            .ask(i: 2, q: "Which plate?", a: "7"),
            .turn(i: 3, role: .you, at: nil, text: "And?", cut: false, files: []),
            .steps(i: 4, line: "Ran code", failed: false, files: [Self.file(9, artifact: 9)]),
        ]
        let answers = ReferenceRules.answers(items: items, reachedStart: true, whole: [:])
        // The second has a figure and no words: a reply still.
        #expect(answers.map(\.id) == [4])
        #expect(answers[0].parts.isEmpty)
        #expect(answers[0].figures.count == 1)
    }

    @Test func aLongQuestionIsCutAndFiguresAreCapped() {
        var items: [HistoryItem] = [.turn(i: 0, role: .you, at: nil, text: String(repeating: "q", count: 1_000), cut: false, files: [])]
        for n in 1...40 { items.append(.steps(i: n, line: "Ran code", failed: false, files: [Self.file(n, artifact: n)])) }
        let reply = ReferenceRules.answers(items: items, reachedStart: true, whole: [:])[0]
        #expect(reply.question?.count == ReferenceRules.questionLimit)
        #expect(reply.figures.count == ReferenceRules.figureLimit)
    }

    @Test func theCaptionIsTheTimeAndThePlaceOnceTheStartIsRead() {
        #expect(ReferenceRules.caption(at: Self.at, index: 1, count: 3, final: true, now: Self.now,
                                       calendar: Self.calendar, locale: Self.locale)
                == "Claude\u{2019}s answer · 8:47 · 2 of 3")
        #expect(ReferenceRules.caption(at: Self.at, index: 0, count: 1, final: false, now: Self.now,
                                       calendar: Self.calendar, locale: Self.locale)
                == "Claude\u{2019}s answer · 8:47")
        #expect(ReferenceRules.caption(at: nil, index: 2, count: 3, final: true, now: Self.now,
                                       calendar: Self.calendar, locale: Self.locale)
                == "Claude\u{2019}s answer · 3 of 3")
    }

    @Test func theTimeAloneOnTheDayElseTheDayToo() {
        #expect(ReferenceRules.when(Self.at, now: Self.now, calendar: Self.calendar, locale: Self.locale) == "8:47")
        let yesterday = ReferenceRules.when(Self.at.addingTimeInterval(-86_400), now: Self.now,
                                            calendar: Self.calendar, locale: Self.locale)
        #expect(yesterday.contains("21"))
        #expect(yesterday.contains("Oct"))
        #expect(yesterday.contains("8:47"))
    }

    @Test func theSourceLineNamesTheSessionProjectAndTime() {
        let line = ReferenceRules.sourceLine(session: Self.session, at: Self.at)
        // The date and time are Keep's, in the Mac's own zone and words.
        #expect(line == "\u{2014} Claude, in \u{201C}Plate reader QC\u{201D} (Assay development), "
                + "\(KeepRules.longDate(Self.at)), \(KeepRules.longTime(Self.at))")
        #expect(ReferenceRules.sourceLine(session: Self.session, at: nil)
                == "\u{2014} Claude, in \u{201C}Plate reader QC\u{201D} (Assay development)")
        // An untitled session goes by its project, as it does everywhere.
        #expect(ReferenceRules.sourceLine(session: Self.untitled, at: nil)
                == "\u{2014} Claude, in \u{201C}Assay development\u{201D} (Assay development)")
    }

    @Test func theCopiedTextIsTrimmedThenSourcedAndLinked() {
        let text = ReferenceRules.copyText("  Eleven passed.\u{2028}One didn\u{2019}t.\n\n", session: Self.session, at: nil)
        #expect(text == "Eleven passed.\nOne didn\u{2019}t.\n\n\u{2014} Claude, in \u{201C}Plate reader QC\u{201D} (Assay development)\n"
                + "bench://session?project=00000000-0000-4000-8000-0000000000aa&frame=00000000-0000-4000-8000-000000000001")
    }

    @Test func plainTextIsTheSystemFontInTheLabelColour() {
        let text = ReferenceRules.plainText("Hello")
        var range = NSRange()
        let attributes = text.attributes(at: 0, effectiveRange: &range)
        #expect(range == NSRange(location: 0, length: 5))
        #expect((attributes[.font] as? NSFont)?.pointSize == 13)
        #expect(attributes[.foregroundColor] as? NSColor == .labelColor)
        #expect((attributes[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacing == 8)
    }
}
