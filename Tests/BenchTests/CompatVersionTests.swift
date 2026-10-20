// CompatVersionTests.swift — Claude Science's version against the one Capsid
// was checked with, and the plain note when they differ (DESIGN.md,
// Diagnostics). Made-up versions only.
import Foundation
import Testing
@testable import Bench

struct ScienceVersionTests {
    // MARK: Reading a version

    @Test func aVersionIsWholeNumbersJoinedByDots() {
        #expect(ScienceVersion.parse("0.1.63") == [0, 1, 63])
        #expect(ScienceVersion.parse(" 2.10 ") == [2, 10])
        #expect(ScienceVersion.parse("v1.2.3") == [1, 2, 3])
        #expect(ScienceVersion.parse("7") == [7])
    }

    @Test func anythingElseIsNotAVersion() {
        for text in ["", "unknown", "0.1.63-rc1", "0.1.x", "1..2", ".1", "1.", "+1.2", "1.2.3.4.5.6.7", "٣.١", "0.1.99999999999"] {
            #expect(ScienceVersion.parse(text) == nil, "\(text)")
        }
    }

    // MARK: Comparing

    private func relation(_ running: String?, _ checked: String = "0.1.63") -> ScienceVersion.Relation {
        ScienceVersion.relation(running: running, checkedWith: checked)
    }

    @Test func theSameVersionIsTheSame() {
        #expect(relation("0.1.63") == .same)
        // Trailing zeros say nothing.
        #expect(relation("0.1.63.0") == .same)
        #expect(relation(" 0.1.63\n") == .same)
        #expect(relation("v0.1.63") == .same)
    }

    @Test func versionsAreComparedAsNumbersNotAsText() {
        #expect(relation("0.1.64") == .newer)
        #expect(relation("0.2.0") == .newer)
        #expect(relation("1.0.0") == .newer)
        // "9" sorts after "63" as text; as a number it is older.
        #expect(relation("0.1.9") == .older)
        #expect(relation("0.1.100") == .newer)
        #expect(relation("0.0.99") == .older)
        #expect(relation("0.1.63.1") == .newer)
    }

    @Test func aVersionThatCantBeOrderedIsDifferentNotSame() {
        #expect(relation("0.1.64-rc1") == .different)
        // Even one that begins like the checked version.
        #expect(relation("0.1.63-rc1") == .different)
        #expect(relation("nightly") == .different)
    }

    @Test func noVersionIsUnknown() {
        #expect(relation(nil) == .unknown)
        #expect(relation("") == .unknown)
        #expect(relation("  ") == .unknown)
        // What `parseCLIStatus` says when the field is missing.
        #expect(relation("unknown") == .unknown)
    }

    // MARK: What Diagnostics says

    @Test func theSameVersionIsOneTickedLine() {
        #expect(ScienceVersion.lines(running: "0.1.63", checkedWith: "0.1.63")
                == ["✓ Claude Science 0.1.63; Capsid was last checked with 0.1.63"])
    }

    @Test func aDifferentVersionGetsAPlainNoteAboutThePage() throws {
        let newer = ScienceVersion.lines(running: "0.1.65", checkedWith: "0.1.63")
        try #require(newer.count == 2)
        #expect(newer[0] == "• Claude Science 0.1.65; Capsid was last checked with 0.1.63")
        #expect(newer[1] == "  That is a newer Claude Science than Capsid was checked with, so features that depend on its page (the tab commands, the readouts, Approve) may need a look.")

        let older = ScienceVersion.lines(running: "0.1.50", checkedWith: "0.1.63")
        try #require(older.count == 2)
        #expect(older[1].contains("an older Claude Science than Capsid was checked with"))

        let odd = ScienceVersion.lines(running: "0.1.64-rc1", checkedWith: "0.1.63")
        try #require(odd.count == 2)
        #expect(odd[1].contains("not the Claude Science Capsid was checked with"))
        #expect(odd[1].hasSuffix("may need a look."))
    }

    @Test func aVersionNotReportedIsSaidSoWithoutAWarning() {
        let lines = ScienceVersion.lines(running: "unknown", checkedWith: "0.1.63")
        #expect(lines == ["• Claude Science didn't say which version it is; Capsid was last checked with 0.1.63"])
        #expect(ScienceVersion.lines(running: nil, checkedWith: "0.1.63") == lines)
    }

    @Test func theLinesUseTheVersionAsReportedWithoutItsWhitespace() {
        #expect(ScienceVersion.lines(running: " 0.1.63\n", checkedWith: "0.1.63").first?.contains("Claude Science 0.1.63;") == true)
    }

    @Test func theCheckedVersionIsARealVersion() {
        #expect(ScienceVersion.parse(CompatInventory.checkedWith) != nil)
        // The default argument is the constant.
        #expect(ScienceVersion.lines(running: CompatInventory.checkedWith).count == 1)
        #expect(ScienceVersion.relation(running: CompatInventory.checkedWith) == .same)
    }
}
