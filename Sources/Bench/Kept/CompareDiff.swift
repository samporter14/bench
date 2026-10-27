// CompareDiff.swift — Compare's Text Changes (DESIGN.md, Compare): the lines of
// one text against the lines of another, as the source text says them. Myers'
// O(ND) difference on the lines (each line a number, so a comparison is cheap),
// after the common head and tail are set aside, with three bounds: at most
// `lineLimit` lines a side, at most `editLimit` lines added and removed, and at
// most `workLimit` steps. Past any of them the answer is that there are too many
// lines or changes to list, with the counts, never part of a list shown as if it
// were all of it. Lines are compared by their bytes (UTF-8), so two spellings of
// "é" are two lines, as they are two files. Pure and `Sendable`: it runs off the
// main actor, and stops when its task is cancelled.
import Foundation

enum CompareDiff {
    /// More lines than this on either side is too many to list.
    static let lineLimit = 20_000
    /// More lines added and removed than this, together, is too many to list (the D of Myers' O(ND)).
    static let editLimit = 2_000
    /// Steps of the search (diagonals tried and lines matched): the bound on time, whatever the lines are.
    static let workLimit = 30_000_000

    enum Kind: Equatable, Sendable {
        /// In both.
        case same
        /// Only in the left side's text (marked −).
        case removed
        /// Only in the right side's text (marked +).
        case added
    }

    /// One line of the single column: what it says, and its number in each side that has it (from 1).
    struct Line: Equatable, Sendable {
        let kind: Kind
        let text: String
        let left: Int?
        let right: Int?
    }

    /// A text as Compare reads it: its lines, and whether it ends with a line break.
    struct Lines: Equatable, Sendable {
        let lines: [String]
        let endsWithLineBreak: Bool

        /// `text` with its line endings already LF (`ShelfDocumentReading.normalized`). An empty text has no lines; a
        /// final line break ends the last line and doesn't start another.
        init(_ text: String) {
            guard !text.isEmpty else {
                lines = []
                endsWithLineBreak = false
                return
            }
            var parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            endsWithLineBreak = parts.last == ""
            if endsWithLineBreak { parts.removeLast() }
            lines = parts
        }
    }

    enum Outcome: Equatable, Sendable {
        /// The two texts are the same, byte for byte.
        case identical
        /// Every line is the same, and only one of them ends with a line break: said so, never "No text changes".
        case onlyLastLineBreak(leftEnds: Bool)
        /// The whole of both texts, line by line, each change's removed lines before its added ones.
        case changes([Line])
        /// A side has more than `lineLimit` lines.
        case tooManyLines(left: Int, right: Int)
        /// More than `editLimit` lines changed, or the search ran past `workLimit`.
        case tooManyChanges(left: Int, right: Int)

        /// The same comparison seen from the other side: what was added is removed, and the reverse.
        func inverted() -> Outcome {
            switch self {
            case .identical: return .identical
            case .onlyLastLineBreak(let leftEnds): return .onlyLastLineBreak(leftEnds: !leftEnds)
            case .tooManyLines(let left, let right): return .tooManyLines(left: right, right: left)
            case .tooManyChanges(let left, let right): return .tooManyChanges(left: right, right: left)
            case .changes(let lines):
                return .changes(CompareDiff.ordered(lines.map { line in
                    switch line.kind {
                    case .same: Line(kind: .same, text: line.text, left: line.right, right: line.left)
                    case .removed: Line(kind: .added, text: line.text, left: nil, right: line.left)
                    case .added: Line(kind: .removed, text: line.text, left: line.right, right: nil)
                    }
                }))
            }
        }
    }

    // MARK: Comparing

    /// The changes from `left` to `right`, two normalized texts. Throws `CancellationError` when its task is cancelled.
    static func compare(_ left: String, _ right: String,
                        lineLimit: Int = lineLimit, editLimit: Int = editLimit, workLimit: Int = workLimit) throws -> Outcome {
        if left.utf8.elementsEqual(right.utf8) { return .identical }
        let a = Lines(left), b = Lines(right)
        guard a.lines.count <= lineLimit, b.lines.count <= lineLimit else {
            return .tooManyLines(left: a.lines.count, right: b.lines.count)
        }
        // Each distinct line a number, by its bytes.
        var numbers: [Data: Int32] = [:]
        func number(_ line: String) -> Int32 {
            let key = Data(line.utf8)
            if let known = numbers[key] { return known }
            let next = Int32(numbers.count)
            numbers[key] = next
            return next
        }
        let x = a.lines.map(number), y = b.lines.map(number)
        try Task.checkCancellation()
        // The common head and tail are the same lines whatever lies between.
        var head = 0
        while head < x.count, head < y.count, x[head] == y[head] { head += 1 }
        var tail = 0
        while tail < x.count - head, tail < y.count - head, x[x.count - 1 - tail] == y[y.count - 1 - tail] { tail += 1 }
        let middleX = Array(x[head..<(x.count - tail)]), middleY = Array(y[head..<(y.count - tail)])
        guard let script = try myers(middleX, middleY, editLimit: editLimit, workLimit: workLimit) else {
            return .tooManyChanges(left: a.lines.count, right: b.lines.count)
        }
        if script.allSatisfy({ $0 == .same }), x.count == y.count {
            return .onlyLastLineBreak(leftEnds: a.endsWithLineBreak)
        }
        var lines: [Line] = []
        lines.reserveCapacity(x.count + y.count - head - tail)
        for i in 0..<head { lines.append(Line(kind: .same, text: a.lines[i], left: i + 1, right: i + 1)) }
        var i = head, j = head
        for step in script {
            switch step {
            case .same:
                lines.append(Line(kind: .same, text: a.lines[i], left: i + 1, right: j + 1))
                i += 1
                j += 1
            case .removed:
                lines.append(Line(kind: .removed, text: a.lines[i], left: i + 1, right: nil))
                i += 1
            case .added:
                lines.append(Line(kind: .added, text: b.lines[j], left: nil, right: j + 1))
                j += 1
            }
        }
        for k in 0..<tail {
            lines.append(Line(kind: .same, text: a.lines[i + k], left: i + k + 1, right: j + k + 1))
        }
        return .changes(ordered(lines))
    }

    /// Each run of changed lines with its removed lines first, then its added ones, each in their own order: one shape
    /// for every comparison, so the one seen from the other side (`inverted`) is the same shape too.
    static func ordered(_ lines: [Line]) -> [Line] {
        var out: [Line] = []
        out.reserveCapacity(lines.count)
        var removed: [Line] = [], added: [Line] = []
        func flush() {
            out += removed
            out += added
            removed.removeAll(keepingCapacity: true)
            added.removeAll(keepingCapacity: true)
        }
        for line in lines {
            switch line.kind {
            case .same:
                flush()
                out.append(line)
            case .removed: removed.append(line)
            case .added: added.append(line)
            }
        }
        flush()
        return out
    }

    /// The runs of changed lines: where each starts in `lines`, and how many it has.
    static func changes(in lines: [Line]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for (index, line) in lines.enumerated() {
            if line.kind == .same {
                if let begun = start { runs.append(begun..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let begun = start { runs.append(begun..<lines.count) }
        return runs
    }

    // MARK: Myers

    /// The shortest script from `a` to `b` (Myers 1986, the greedy forward search, with each round's furthest points
    /// kept for the way back), or nil past `editLimit` changes or `workLimit` steps.
    static func myers(_ a: [Int32], _ b: [Int32], editLimit: Int, workLimit: Int) throws -> [Kind]? {
        let n = a.count, m = b.count
        if n == 0 { return Array(repeating: .added, count: m) }
        if m == 0 { return Array(repeating: .removed, count: n) }
        let most = n + m
        guard most > 0 else { return [] }
        let limit = min(most, editLimit)
        let offset = most + 1
        // v[k + offset]: the furthest x reached on diagonal k.
        var v = [Int32](repeating: 0, count: 2 * most + 3)
        // trace[d]: v over diagonals -(d-1)...(d-1), as it was before round d (empty for round 0).
        var trace: [[Int32]] = []
        var work = 0
        for d in 0...limit {
            if d % 32 == 0 { try Task.checkCancellation() }
            trace.append(d == 0 ? [] : Array(v[(offset - d + 1)...(offset + d - 1)]))
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = Int(v[offset + k + 1])
                } else {
                    x = Int(v[offset + k - 1]) + 1
                }
                var y = x - k
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                    work += 1
                }
                work += 1
                if work > workLimit { return nil }
                v[offset + k] = Int32(x)
                if x >= n, y >= m { return backtrack(trace, n: n, m: m, d: d) }
            }
        }
        return nil
    }

    private static func backtrack(_ trace: [[Int32]], n: Int, m: Int, d: Int) -> [Kind] {
        var script: [Kind] = []
        script.reserveCapacity(n + m)
        var x = n, y = m
        var round = d
        while round > 0 {
            let saved = trace[round]
            // Diagonal k of round `round` is saved[k + round - 1].
            func at(_ k: Int) -> Int { Int(saved[k + round - 1]) }
            let k = x - y
            let previous = (k == -round || (k != round && at(k - 1) < at(k + 1))) ? k + 1 : k - 1
            let px = at(previous), py = px - previous
            while x > px, y > py {
                script.append(.same)
                x -= 1
                y -= 1
            }
            if x == px {
                script.append(.added)
                y -= 1
            } else {
                script.append(.removed)
                x -= 1
            }
            round -= 1
        }
        while x > 0, y > 0 {
            script.append(.same)
            x -= 1
            y -= 1
        }
        return script.reversed()
    }
}
