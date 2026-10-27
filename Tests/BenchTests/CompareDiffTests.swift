// CompareDiffTests.swift — Compare's Text Changes (Kept/CompareDiff.swift): the
// same text, one line added or taken away, repeated lines, Unicode by its bytes,
// a byte order mark and Windows line ends read as the Shelf's card reads them,
// empty texts, a last line break, the shape every change takes, the script
// rebuilding both texts, the other side's view, and the bounds: too many lines,
// too many changes, a search too long, and a cancelled one, each quick.
import Foundation
import Testing
@testable import Bench

struct CompareDiffTests {
    private func changes(_ left: String, _ right: String) throws -> [CompareDiff.Line] {
        guard case .changes(let lines) = try CompareDiff.compare(left, right) else {
            Issue.record("expected changes")
            return []
        }
        return lines
    }

    private func kinds(_ lines: [CompareDiff.Line]) -> String {
        lines.map { switch $0.kind { case .same: "=" ; case .added: "+" ; case .removed: "-" } }.joined()
    }

    @Test func theSameTextHasNoChanges() throws {
        #expect(try CompareDiff.compare("a\nb\n", "a\nb\n") == .identical)
        #expect(try CompareDiff.compare("", "") == .identical)
    }

    @Test func aByteOrderMarkAndWindowsLineEndsAreReadAsTheCardReadsThem() throws {
        let windows = ShelfDocumentReading.normalized("\u{FEFF}# Plate reader QC\r\nEleven plates pass.\r\nRepeat plate 7.\r\n")
        let plain = ShelfDocumentReading.normalized("# Plate reader QC\nEleven plates pass.\nRepeat plate 7.\n")
        #expect(windows == plain)
        #expect(try CompareDiff.compare(windows, plain) == .identical)
        // An old Mac file's lone carriage returns too.
        #expect(ShelfDocumentReading.normalized("a\rb\r") == "a\nb\n")
    }

    @Test func oneLineAddedOrTakenAway() throws {
        let added = try changes("a\nb\nc\n", "a\nb\nx\nc\n")
        #expect(kinds(added) == "==+=")
        #expect(added[2] == CompareDiff.Line(kind: .added, text: "x", left: nil, right: 3))
        let removed = try changes("a\nb\nx\nc\n", "a\nb\nc\n")
        #expect(kinds(removed) == "==-=")
        #expect(removed[2] == CompareDiff.Line(kind: .removed, text: "x", left: 3, right: nil))
        // A line changed: its old words first, then its new ones.
        #expect(kinds(try changes("a\nb\nc\n", "a\nB\nc\n")) == "=-+=")
    }

    @Test func repeatedLinesAreCountedNotMerged() throws {
        #expect(kinds(try changes("a\na\na\n", "a\na\n")) == "==-")
        #expect(kinds(try changes("x\na\nx\na\n", "x\na\nx\na\nx\na\n")) == "====++")
    }

    @Test func unicodeIsComparedByItsBytes() throws {
        // "é" written as one character and as e with an accent are two lines, as they are two files.
        let lines = try changes("caf\u{00E9}\n\u{1F9EB} wells\n", "cafe\u{0301}\n\u{1F9EB} wells\n")
        #expect(kinds(lines) == "-+=")
        #expect(lines[2].text == "\u{1F9EB} wells")
        #expect(try CompareDiff.compare("\u{2032} Z\u{2032}\n", "\u{2032} Z\u{2032}\n") == .identical)
    }

    @Test func emptyTexts() throws {
        #expect(kinds(try changes("", "a\n")) == "+")
        #expect(kinds(try changes("a\n", "")) == "-")
        #expect(kinds(try changes("", "\n")) == "+")
    }

    @Test func aLastLineBreakAloneIsSaidAndIsNeverNoChanges() throws {
        #expect(try CompareDiff.compare("a\nb", "a\nb\n") == .onlyLastLineBreak(leftEnds: false))
        #expect(try CompareDiff.compare("a\nb\n", "a\nb") == .onlyLastLineBreak(leftEnds: true))
        // An extra blank line is a line.
        #expect(kinds(try changes("a\n", "a\n\n")) == "=+")
    }

    @Test func eachChangeHasItsRemovedLinesBeforeItsAddedOnes() throws {
        let lines = try changes("1\n2\n3\n4\n5\n", "1\nB\nC\n4\nE\n")
        #expect(kinds(lines) == "=--++=-+")
        #expect(CompareDiff.changes(in: lines) == [1..<5, 6..<8])
    }

    /// A small generator, so the cases are the same on every run.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test func theScriptRebuildsBothTextsAndIsTheShortest() throws {
        var random = Seeded(state: 7)
        for _ in 0..<200 {
            let left = (0..<Int.random(in: 0..<14, using: &random)).map { _ in String("abcd".randomElement(using: &random)!) }
            let right = (0..<Int.random(in: 0..<14, using: &random)).map { _ in String("abcd".randomElement(using: &random)!) }
            let a = left.map { $0 + "\n" }.joined(), b = right.map { $0 + "\n" }.joined()
            let outcome = try CompareDiff.compare(a, b)
            if a == b {
                #expect(outcome == .identical)
                continue
            }
            guard case .changes(let lines) = outcome, case .changes(let other) = outcome.inverted() else {
                Issue.record("expected changes for \(left) and \(right)")
                continue
            }
            #expect(lines.filter { $0.kind != .added }.map(\.text) == left)
            #expect(lines.filter { $0.kind != .removed }.map(\.text) == right)
            // As few lines changed as the longest common subsequence allows.
            let edits = lines.filter { $0.kind != .same }.count
            #expect(edits == left.count + right.count - 2 * Self.lcs(left, right))
            // Seen from the other side, the same lines rebuild the other way round, as few as before.
            #expect(other.filter { $0.kind != .added }.map(\.text) == right)
            #expect(other.filter { $0.kind != .removed }.map(\.text) == left)
            #expect(other.filter { $0.kind != .same }.count == edits)
        }
    }

    private static func lcs(_ a: [String], _ b: [String]) -> Int {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table[0][0]
    }

    @Test func theOtherSidesViewSwapsWhatWasAddedAndRemoved() throws {
        let outcome = try CompareDiff.compare("a\nb\nc\n", "a\nB\nc\nd\n")
        guard case .changes(let lines) = outcome.inverted() else {
            Issue.record("expected changes")
            return
        }
        #expect(kinds(lines) == "=-+=-")
        #expect(lines[1] == CompareDiff.Line(kind: .removed, text: "B", left: 2, right: nil))
        #expect(lines[2] == CompareDiff.Line(kind: .added, text: "b", left: nil, right: 2))
        #expect(outcome.inverted().inverted() == outcome)
        #expect(CompareDiff.Outcome.tooManyLines(left: 1, right: 2).inverted() == .tooManyLines(left: 2, right: 1))
        #expect(CompareDiff.Outcome.onlyLastLineBreak(leftEnds: true).inverted() == .onlyLastLineBreak(leftEnds: false))
    }

    // MARK: The bounds

    @Test func tooManyLinesIsSaidWithTheCounts() throws {
        let long = (0...CompareDiff.lineLimit).map { "line \($0)\n" }.joined()
        #expect(try CompareDiff.compare(long, "a\n") == .tooManyLines(left: CompareDiff.lineLimit + 1, right: 1))
    }

    @Test func twoTextsWithNoLineInCommonStopQuicklyAsTooManyChanges() throws {
        let left = (0..<3_000).map { "left \($0)\n" }.joined(), right = (0..<3_000).map { "right \($0)\n" }.joined()
        let started = ContinuousClock.now
        let outcome = try CompareDiff.compare(left, right)
        let took = ContinuousClock.now - started
        #expect(outcome == .tooManyChanges(left: 3_000, right: 3_000))
        #expect(took < .seconds(1), "took \(took)")
    }

    @Test func longRunsOfTheSameLineWithChangesThroughoutStopAtTheWorkBound() throws {
        // Twenty thousand identical lines with a change every eight: the snakes are long and the changes many.
        let left = (0..<CompareDiff.lineLimit).map { $0 % 8 == 0 ? "x\($0)\n" : "a\n" }.joined()
        let right = (0..<CompareDiff.lineLimit).map { $0 % 8 == 4 ? "y\($0)\n" : "a\n" }.joined()
        let started = ContinuousClock.now
        let outcome = try CompareDiff.compare(left, right)
        let took = ContinuousClock.now - started
        #expect(outcome == .tooManyChanges(left: CompareDiff.lineLimit, right: CompareDiff.lineLimit))
        #expect(took < .seconds(3), "took \(took)")
    }

    @Test func aSmallWorkBoundIsNeverAPartialList() throws {
        let left = (0..<400).map { "a\($0)\n" }.joined(), right = (0..<400).map { $0 % 3 == 0 ? "b\($0)\n" : "a\($0)\n" }.joined()
        #expect(try CompareDiff.compare(left, right, workLimit: 50) == .tooManyChanges(left: 400, right: 400))
        #expect(try CompareDiff.compare(left, right, editLimit: 10) == .tooManyChanges(left: 400, right: 400))
        guard case .changes = try CompareDiff.compare(left, right) else {
            Issue.record("the same pair within the bounds lists its changes")
            return
        }
    }

    @Test func aCancelledComparisonStops() async throws {
        let left = (0..<15_000).map { "left \($0)\n" }.joined(), right = (0..<15_000).map { "right \($0)\n" }.joined()
        let task = Task.detached { try CompareDiff.compare(left, right, editLimit: 100_000, workLimit: .max) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
