// ReferenceRulesTests.swift — the reference reader's pure rules: which rows
// are answers, the position line, the time, the source line and the copied text.
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

    @Test func onlyClaudesTurnsAreAnswers() {
        let file = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000004", a: nil, name: "z.png", kind: .image, size: nil)
        let page = HistoryPage(total: 6, from: 0, items: [
            .turn(i: 0, role: .you, at: nil, text: "Q", cut: false, files: []),
            .steps(i: 1, line: "Ran a command", failed: false, files: [file]),
            .turn(i: 2, role: .claude, at: Self.at, text: "A", cut: true, files: [file]),
            .plan(i: 3, steps: 2),
            .ask(i: 4, q: "Which?", a: nil),
            .turn(i: 5, role: .claude, at: nil, text: "B", cut: false, files: []),
        ])
        let answers = ReferenceRules.answers(in: page)
        #expect(answers.map(\.i) == [2, 5])
        #expect(answers[0] == ReferenceAnswer(i: 2, at: Self.at, text: "A", cut: true, files: [file]))
        #expect(answers[0].figures == [file])
        #expect(answers[1].figures.isEmpty)
    }

    @Test func thePositionLineCountsWhatWasReadAndSaysSoFarUntilTheStart() {
        #expect(ReferenceRules.positionLine(at: Self.at, index: 1, count: 3, final: true, now: Self.now,
                                            calendar: Self.calendar, locale: Self.locale)
                == "Claude\u{2019}s answer · 8:47 · 2 of 3")
        #expect(ReferenceRules.positionLine(at: Self.at, index: 0, count: 1, final: false, now: Self.now,
                                            calendar: Self.calendar, locale: Self.locale)
                == "Claude\u{2019}s answer · 8:47 · 1 of 1 so far")
        #expect(ReferenceRules.positionLine(at: nil, index: 2, count: 3, final: true, now: Self.now,
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
